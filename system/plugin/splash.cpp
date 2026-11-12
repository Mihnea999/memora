// splash.cpp: the desktop picture from the very first frame after logging in.
//
// The login screen (shell/greeter.qml) ends on your desktop picture, sharp, and
// leaves that frame in /var/lib/memora/login-frame (XRGB8888 rows, the size in
// login-frame.size); memora-greeter puts it on the console while the session
// starts. From Hyprland's first frame this draws the same picture over the empty
// background, until the shell's own desktop picture is up and says so
// (`hyprctl memora-splash done [MONITOR]`): then it fades away, which looks like
// nothing at all, since the same picture is under it. So the login goes from
// picture to picture, never through black.
//
// Only a fresh frame counts (written in the last minute): Hyprland started again
// later, or a login without the login screen, shows nothing of it.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/ipc/s1/S1.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Texture.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <drm_fourcc.h>
#include <sys/stat.h>
#include <chrono>
#include <fstream>
#include <format>
#include <sstream>
#include <unordered_map>

using namespace Render;
using namespace Render::GL;

namespace {
    using Clock = std::chrono::steady_clock;

    const char*                 FRAME   = "/var/lib/memora/login-frame";
    constexpr int               FADE_MS = 320;
    constexpr int               MAX_MS  = 20000; // the shell never said: go anyway

    HANDLE                      g_handle = nullptr;
    std::vector<uint8_t>        g_pixels;
    Vector2D                    g_size;
    SP<ITexture>                g_tex;
    bool                        g_on = false;
    Clock::time_point           g_start;
    CHyprSignalListener         g_stage;
    SP<IPC::Socket1::SCommand>  g_cmd;
    // Per monitor: when its fade began (absent: still showing).
    std::unordered_map<std::string, Clock::time_point> g_fading;
    bool                        g_allFading = false;
    Clock::time_point           g_allSince;

    int msSince(Clock::time_point t) {
        return (int)std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - t).count();
    }

    bool loadFrame() {
        struct stat st{};
        const auto  now = time(nullptr);
        if (stat(FRAME, &st) != 0 || now - st.st_mtime > 60 || st.st_mtime > now + 10)
            return false;
        std::ifstream sz(std::string(FRAME) + ".size");
        int           w = 0, h = 0;
        if (!(sz >> w >> h) || w < 64 || h < 64 || w > 16384 || h > 16384 || st.st_size != (off_t)w * h * 4)
            return false;
        std::ifstream f(FRAME, std::ios::binary);
        g_pixels.resize((size_t)w * h * 4);
        if (!f.read((char*)g_pixels.data(), g_pixels.size())) {
            g_pixels.clear();
            return false;
        }
        g_size = {(double)w, (double)h};
        return true;
    }

    void finish() {
        g_on = false;
        g_tex.reset();
        g_pixels.clear();
        g_pixels.shrink_to_fit();
        g_fading.clear();
        g_allFading = false;
        // The listener stays (finish() can run from inside it); it does nothing now.
    }

    // How much of the picture shows on this monitor now (1 until the shell is up).
    float alphaFor(const std::string& name) {
        Clock::time_point since;
        if (auto it = g_fading.find(name); it != g_fading.end())
            since = it->second;
        else if (g_allFading)
            since = g_allSince;
        else
            return 1.F;
        const float t = std::clamp(msSince(since) / (float)FADE_MS, 0.F, 1.F);
        return 1.F - t * t * (3.F - 2.F * t);
    }

    class CSplashPass : public IPassElement {
      public:
        explicit CSplashPass(float a) : m_a(a) {}
        bool                needsLiveBlur(CRenderContext&) override { return false; }
        bool                needsPrecomputeBlur(CRenderContext&) override { return false; }
        const char*         passName() override { return "CMemoraSplashPass"; }
        ePassElementType    type() override { return EK_CUSTOM; }
        bool                disableSimplification(CRenderContext&) override { return true; }
        std::optional<CBox> boundingBox(CRenderContext& ctx) override {
            auto mon = ctx.m_data.pMonitor.lock();
            if (!mon)
                return std::nullopt;
            return CBox{0, 0, mon->m_size.x, mon->m_size.y};
        }

        std::vector<UP<IPassElement>> draw(CRenderContext& ctx) override {
            auto mon = ctx.m_data.pMonitor.lock();
            if (!mon || !g_tex || m_a <= 0)
                return {};
            // Cover the screen, centred (as the login screen and the shell do).
            const double W = mon->m_size.x * mon->m_scale, H = mon->m_size.y * mon->m_scale;
            const double k = std::max(W / g_size.x, H / g_size.y);
            const double w = g_size.x * k, h = g_size.y * k;
            CBox         box{(W - w) / 2.0, (H - h) / 2.0, w, h};
            g_pHyprOpenGL->renderTexture(ctx, g_tex, box.round(), {.a = m_a});
            return {};
        }

      private:
        float m_a = 1;
    };

    void onStage(const Event::SRenderStageEvent& ev) {
        if (!g_on || ev.stage != RENDER_BEGIN || !ev.context || !ev.monitor)
            return;
        auto mon = ev.monitor;
        if (!g_tex) {
            g_tex = g_pHyprRenderer->createTexture(DRM_FORMAT_XRGB8888, g_pixels.data(), (uint32_t)g_size.x * 4, g_size, false, true);
            g_pixels.clear();
            g_pixels.shrink_to_fit();
            if (!g_tex || !g_tex->ok()) {
                finish();
                return;
            }
        }
        if (!g_allFading && msSince(g_start) > MAX_MS) {
            g_allFading = true;
            g_allSince  = Clock::now();
        }
        const float a = alphaFor(mon->m_name);
        if (a > 0.F)
            IHyprRenderer::addPassElement(ev.context->get(), makeUnique<CSplashPass>(a));
        // Keep the fade moving.
        if (a < 1.F && a > 0.F) {
            g_pHyprRenderer->damageMonitor(mon);
            mon->scheduleFrame();
        }
        // Every active monitor has faded: done for good.
        auto mons = State::monitorState()->monitors();
        bool all  = !mons.empty();
        for (auto& m : mons) {
            if (m && alphaFor(m->m_name) > 0.F)
                all = false;
        }
        if (all)
            finish();
    }

    // `hyprctl memora-splash done [MONITOR]`: the shell's own picture is up.
    IPC::Socket1::SResponse onCommand(const IPC::Socket1::SRequest& req) {
        if (!g_on)
            return IPC::Socket1::SResponse(std::string("off\n"));
        std::string rest = req.command.substr(std::min(req.command.size(), std::string("memora-splash").size()));
        std::istringstream in(rest);
        std::string        what, mon;
        in >> what >> mon;
        if (what != "done")
            return IPC::Socket1::SResponse(std::format("showing {}x{}, {} ms\n", g_size.x, g_size.y, msSince(g_start)));
        if (mon.empty()) {
            if (!g_allFading) {
                g_allFading = true;
                g_allSince  = Clock::now();
            }
        } else if (!g_fading.contains(mon))
            g_fading[mon] = Clock::now();
        for (auto& m : State::monitorState()->monitors()) {
            if (m && (mon.empty() || m->m_name == mon)) {
                g_pHyprRenderer->damageMonitor(m);
                m->scheduleFrame();
            }
        }
        return IPC::Socket1::SResponse(std::string("ok\n"));
    }
}

void memoraSplashInit(HANDLE handle) {
    g_handle = handle;
    g_cmd    = HyprlandAPI::registerHyprCtlCommand(handle, IPC::Socket1::SCommand{.name = "memora-splash", .match = IPC::Socket1::COMMAND_MATCH_PREFIX, .handler = onCommand});
    if (!loadFrame())
        return;
    g_on    = true;
    g_start = Clock::now();
    g_stage = Event::bus()->m_events.render.stage.listen([](const Event::SRenderStageEvent& ev) { onStage(ev); });
    for (auto& mon : State::monitorState()->monitors()) {
        if (mon) {
            g_pHyprRenderer->damageMonitor(mon);
            mon->scheduleFrame();
        }
    }
}

void memoraSplashExit() {
    if (g_cmd)
        HyprlandAPI::unregisterHyprCtlCommand(g_handle, g_cmd);
    g_cmd.reset();
    finish();
    g_stage.reset();
}
