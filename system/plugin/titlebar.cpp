// memora-titlebar: a Mac-like title bar for apps that leave their frame to the
// system. Some apps (egui/winit ones like GridCraft, many Qt apps) ask the
// compositor to draw their title bar ("server-side decorations", xdg-decoration)
// and draw none themselves; Hyprland draws none either, so they had no way to be
// closed, minimized or moved with the mouse. These windows get a bar here:
// red/yellow/green buttons on the left (symbols when the pointer is over them),
// the title in the middle, drag to move, double-click to fill the screen.
// Apps that draw their own frame (GTK, Chromium, Memora's) are left alone.
// Built for Hyprland 0.57 together with minimize.cpp (build.sh).
#define WLR_USE_UNSTABLE
// The standard library first: it must not see the #define below.
#include <algorithm>
#include <any>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <format>
#include <fstream>
#include <functional>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <unordered_map>
#include <variant>
#include <vector>
// The decoration protocol keeps which mode it told each app; it is private.
#define private public
#include <hyprland/src/protocols/XDGDecoration.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#undef private

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/ipc/s1/S1.hpp>
#include <hyprland/src/render/decorations/IHyprWindowDecoration.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/state/ViewHitTester.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowBackend.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include <hyprland/src/devices/ITouch.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/config/supplementary/executor/Executor.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/protocols/LayerShell.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <fstream>
#include <sys/stat.h>
#include <vector>
#include <linux/input-event-codes.h>

using namespace Render::GL;

namespace {
    constexpr int   BAR_H   = 32; // logical px
    constexpr int   BTN     = 14; // button diameter
    constexpr int   BTN_GAP = 9;  // between buttons
    constexpr int   PAD     = 13; // left edge to the first button
    constexpr int   ZONE    = PAD + 3 * BTN + 2 * BTN_GAP + 6;

    // The system typeface (System Settings > Appearance; memora-theme writes it).
    const std::string& font() {
        static std::string path = std::string(getenv("HOME") ? getenv("HOME") : "") + "/.config/memora/font";
        static time_t      seen = -1;
        static std::string val  = "Inter";
        struct stat        st {};
        if (stat(path.c_str(), &st) == 0 && st.st_mtime != seen) {
            seen = st.st_mtime;
            std::ifstream f(path);
            std::string   s;
            std::getline(f, s);
            val = s.empty() || s.size() > 64 ? "Inter" : s;
        }
        return val;
    }

    // Light or dark, as Memora's appearance (memora-theme writes it).
    bool dark() {
        static std::string path = std::string(getenv("HOME") ? getenv("HOME") : "") + "/.config/memora/theme";
        static time_t      seen = -1;
        static bool        val  = true;
        struct stat        st {};
        if (stat(path.c_str(), &st) == 0 && st.st_mtime != seen) {
            seen = st.st_mtime;
            std::ifstream f(path);
            std::string   s;
            f >> s;
            val = s != "light";
        }
        return val;
    }
}

class CMemoraBar;
std::vector<WP<CMemoraBar>> g_bars;
static void                 publishBars();

class CMemoraBarPass : public IPassElement {
  public:
    CMemoraBarPass(CMemoraBar* bar, float a) : m_bar(bar), m_a(a) {}
    std::vector<UP<IPassElement>> draw(Render::CRenderContext& ctx) override;
    bool                          needsLiveBlur(Render::CRenderContext&) override { return false; }
    bool                          needsPrecomputeBlur(Render::CRenderContext&) override { return false; }
    std::optional<CBox>           boundingBox(Render::CRenderContext& ctx) override;
    const char*                   passName() override { return "CMemoraBarPass"; }
    ePassElementType              type() override { return EK_CUSTOM; }

  private:
    CMemoraBar* m_bar;
    float       m_a;
};

class CMemoraBar : public IHyprWindowDecoration {
  public:
    CMemoraBar(PHLWINDOW w) : IHyprWindowDecoration(w), m_window(w) {
        m_button = Event::bus()->m_events.input.mouse.button.listen([this](IPointer::SButtonEvent e, Event::SCallbackInfo& info) { onButton(e, info); });
        m_move   = Event::bus()->m_events.input.mouse.move.listen([this](Vector2D, Event::SCallbackInfo&) { onMove(); });
        if (auto m = w->m_monitor.lock())
            m->m_scheduledRecalc = true;
    }
    ~CMemoraBar() override {
        std::erase_if(g_bars, [this](const auto& b) { return !b || b.get() == this; });
        publishBars();
    }
    PHLWINDOW owner() { return m_window.lock(); }

    SDecorationPositioningInfo getPositioningInfo() override {
        SDecorationPositioningInfo info;
        info.policy         = DECORATION_POSITION_STICKY;
        info.edges          = DECORATION_EDGE_TOP;
        info.priority       = 5000;
        info.reserved       = true;
        info.desiredExtents = {{0, BAR_H}, {0, 0}};
        return info;
    }
    void onPositioningReply(const SDecorationPositioningReply& reply) override { m_assigned = reply.assignedGeometry; }

    void draw(Render::CRenderContext& ctx, PHLMONITOR, const float& a, const Render::SWindowRenderPresentation&) override {
        if (!validMapped(m_window))
            return;
        Render::IHyprRenderer::addPassElement(ctx, makeUnique<CMemoraBarPass>(this, a));
    }
    eDecorationType  getDecorationType() override { return DECORATION_CUSTOM; }
    void             updateWindow(PHLWINDOW) override { damageEntire(); }
    void             damageEntire() override { g_pHyprRenderer->damageBox(globalBox().expand(2)); }
    eDecorationLayer getDecorationLayer() override { return DECORATION_LAYER_UNDER; }
    uint64_t         getDecorationFlags() override { return DECORATION_ALLOWS_MOUSE_INPUT | DECORATION_PART_OF_MAIN_WINDOW; }
    std::string      getDisplayName() override { return "MemoraBar"; }

    void             titleChanged() {
        m_titleTex = nullptr;
        damageEntire();
    }

    // The bar in global layout coordinates.
    CBox globalBox() {
        if (!validMapped(m_window))
            return {};
        auto w   = m_window.lock();
        CBox box = m_assigned;
        box.translate(g_pDecorationPositioner->getEdgeDefinedPoint(DECORATION_EDGE_TOP, w));
        const auto ws = w->m_workspace;
        if (ws && !(w->m_state & Desktop::View::WINDOW_STATE_PINNED))
            box.translate(ws->m_renderOffset->value());
        return box;
    }

    void render(Render::CRenderContext& ctx, PHLMONITOR mon, float a) {
        auto w = m_window.lock();
        if (!w || !mon)
            return;
        const bool  DARK   = dark();
        const bool  ACTIVE = Desktop::focusState()->window() == w;
        const float S      = mon->m_scale;

        const CBox  G = globalBox();
        CBox        bar{G.x - mon->m_position.x, G.y - mon->m_position.y, G.w, G.h};
        bar.translate(w->presentation().floatingOffset());
        const double rounding = w->presentation().rounding();
        // Extends under the window, so only the top corners show rounded.
        CBox fill = bar;
        fill.h += rounding * 2 + 4;
        fill.scale(S).round();
        if (fill.w < 1 || fill.h < 1)
            return;

        CHyprColor bg = DARK ? (ACTIVE ? CHyprColor(0.17, 0.17, 0.18, 1) : CHyprColor(0.13, 0.13, 0.14, 1))
                             : (ACTIVE ? CHyprColor(0.91, 0.91, 0.92, 1) : CHyprColor(0.95, 0.95, 0.96, 1));
        bg.a *= a;
        CBox clip = bar;
        clip.scale(S).round();
        g_pHyprOpenGL->scissor(ctx, clip);
        g_pHyprOpenGL->renderRect(ctx, fill, bg, {.round = (int)std::round(rounding * S), .roundingPower = w->presentation().roundingPower()});
        // A hairline between the bar and the app.
        const double hair = std::max(1.0, (double)std::round(S));
        CBox         line{clip.x, clip.y + clip.h - hair, clip.w, hair};
        g_pHyprOpenGL->renderRect(ctx, line, DARK ? CHyprColor(0, 0, 0, 0.45 * a) : CHyprColor(0, 0, 0, 0.10 * a), {});

        // The buttons: red, yellow, green; grey on a window in the background
        // (coloured again while the pointer is over them), symbols on hover.
        static const CHyprColor COLORS[3] = {CHyprColor(1.0, 0.373, 0.341, 1), CHyprColor(0.996, 0.737, 0.18, 1), CHyprColor(0.157, 0.784, 0.251, 1)};
        const CHyprColor        IDLE      = DARK ? CHyprColor(0.30, 0.30, 0.32, 1) : CHyprColor(0.80, 0.80, 0.82, 1);
        const int               bs        = std::round(BTN * S);
        for (int i = 0; i < 3; i++) {
            const double cx = bar.x + PAD + i * (BTN + BTN_GAP);
            const double cy = bar.y + (BAR_H - BTN) / 2.0;
            CBox         b{std::round(cx * S), std::round(cy * S), (double)bs, (double)bs};
            CHyprColor   c = (ACTIVE || m_hover) ? COLORS[i] : IDLE;
            c.a *= a;
            g_pHyprOpenGL->renderRect(ctx, b, c, {.round = bs / 2, .roundingPower = 2.F});
            if (m_hover) {
                auto& tex = m_symbols[i];
                if (!tex || m_symbolScale != S) {
                    static const char* SYM[3] = {"×", "−", "+"};
                    tex                       = g_pHyprRenderer->renderText(SYM[i], CHyprColor(0.2, 0.05, 0.02, 0.85), std::round(11 * S), false, font(), 0, 700);
                }
                if (tex) {
                    CBox t{b.x + (b.w - tex->m_size.x) / 2.0, b.y + (b.h - tex->m_size.y) / 2.0, tex->m_size.x, tex->m_size.y};
                    g_pHyprOpenGL->renderTexture(ctx, tex, t.round(), {.a = a});
                }
            }
        }
        m_symbolScale = S;

        // The title, in the middle.
        const std::string title = w->metadata().title();
        const int         maxW  = std::max(0, (int)std::round((bar.w - 2 * ZONE) * S));
        if (!m_titleTex || title != m_title || m_titleActive != ACTIVE || m_titleDark != DARK || m_titleW != maxW || m_titleFont != font()) {
            m_title       = title;
            m_titleFont   = font();
            m_titleActive = ACTIVE;
            m_titleDark   = DARK;
            m_titleW      = maxW;
            CHyprColor tc = DARK ? (ACTIVE ? CHyprColor(0.90, 0.90, 0.92, 1) : CHyprColor(0.56, 0.56, 0.58, 1))
                                 : (ACTIVE ? CHyprColor(0.24, 0.24, 0.26, 1) : CHyprColor(0.60, 0.60, 0.62, 1));
            m_titleTex    = (title.empty() || maxW < 20) ? nullptr : g_pHyprRenderer->renderText(title, tc, std::round(10.5 * S), false, font(), maxW, 600);
        }
        if (m_titleTex) {
            CBox t{clip.x + (clip.w - m_titleTex->m_size.x) / 2.0, clip.y + (clip.h - m_titleTex->m_size.y) / 2.0, m_titleTex->m_size.x, m_titleTex->m_size.y};
            g_pHyprOpenGL->renderTexture(ctx, m_titleTex, t.round(), {.a = a});
        }
        g_pHyprOpenGL->scissor(ctx, nullptr);
    }

    // Touch: is this point on the bar, and on which button (-1 none)?
    bool touchHits(const Vector2D& p) {
        if (!validMapped(m_window))
            return false;
        const auto B = globalBox();
        return p.x >= B.x && p.y >= B.y && p.x < B.x + B.w && p.y < B.y + BAR_H;
    }
    int  touchButton(const Vector2D& p) {
        // A finger needs more room than a pointer.
        const auto R = p - globalBox().pos();
        for (int i = 0; i < 3; i++) {
            const double cx = PAD + i * (BTN + BTN_GAP) + BTN / 2.0, cy = BAR_H / 2.0;
            if (std::hypot(R.x - cx, R.y - cy) <= BTN / 2.0 + 9)
                return i;
        }
        return -1;
    }
    void touchAct(int which) { act(which); }

  private:
    // Which button is under the pointer (0 close, 1 minimize, 2 zoom), -1 none.
    int buttonAt(const Vector2D& rel) {
        for (int i = 0; i < 3; i++) {
            const double cx = PAD + i * (BTN + BTN_GAP) + BTN / 2.0, cy = BAR_H / 2.0;
            if (std::hypot(rel.x - cx, rel.y - cy) <= BTN / 2.0 + 3)
                return i;
        }
        return -1;
    }
    Vector2D rel() { return g_pInputManager->getMouseCoordsInternal() - globalBox().pos(); }

    // The pointer is over this bar, and nothing (another window, a panel) is on top of it.
    bool pointerHere() {
        if (!validMapped(m_window))
            return false;
        auto       w = m_window.lock();
        const auto R = rel();
        if (R.x < 0 || R.y < 0 || R.x >= globalBox().w || R.y >= BAR_H)
            return false;
        if (g_pSeatManager->m_seatGrab && !g_pSeatManager->m_seatGrab->accepts(w->wlSurface()->resource()))
            return false;
        const auto              MOUSE = g_pInputManager->getMouseCoordsInternal();
        Desktop::CViewHitTester hit{*Desktop::viewState()};
        if (hit.windowAt(MOUSE, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::ALLOW_FLOATING) != w)
            return false;
        auto mon = Desktop::focusState()->monitor();
        if (!mon)
            return false;
        PHLLS    ls;
        Vector2D local;
        for (auto layer : {ZWLR_LAYER_SHELL_V1_LAYER_TOP, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY}) {
            hit.layerSurfaceAt(MOUSE, &mon->m_layerSurfaceLayers[layer], &local, &ls);
            if (ls)
                return false;
        }
        return true;
    }

    void onMove() {
        const bool over = pointerHere() && rel().x < ZONE;
        if (over != m_hover) {
            m_hover = over;
            damageEntire();
        }
        if (m_dragPending && !m_dragging && validMapped(m_window)) {
            const auto d = g_pInputManager->getMouseCoordsInternal() - m_downAt;
            if (std::abs(d.x) + std::abs(d.y) > 3) {
                m_dragPending = false;
                g_layoutManager->beginDragTarget(m_window.lock()->layoutTarget(), MBIND_MOVE);
                m_dragging = true;
            }
        }
    }

    void onButton(const IPointer::SButtonEvent& e, Event::SCallbackInfo& info) {
        // Right click on the bar: the window's menu (the shell's snap/WindowMenu.qml).
        if (e.button == BTN_RIGHT && e.state == WL_POINTER_BUTTON_STATE_PRESSED && pointerHere()) {
            auto w = m_window.lock();
            if (w && !w->hasPopupAt(g_pInputManager->getMouseCoordsInternal())) {
                info.cancelled = true;
                m_rightSwallowed = true;
                Config::Supplementary::executor()->spawn(std::format("memora-shell window-menu 0x{:x}", (uintptr_t)w.get()));
            }
            return;
        }
        if (e.button == BTN_RIGHT && e.state != WL_POINTER_BUTTON_STATE_PRESSED && m_rightSwallowed) {
            m_rightSwallowed = false;
            info.cancelled = true;
            return;
        }
        if (e.button != BTN_LEFT)
            return;
        auto w = m_window.lock();
        if (e.state != WL_POINTER_BUTTON_STATE_PRESSED) {
            if (m_swallowed)
                info.cancelled = true;
            m_swallowed = false;
            if (m_dragging) {
                g_layoutManager->endDragTarget();
                m_dragging = false;
            }
            m_dragPending = false;
            if (m_pressed >= 0 && w && pointerHere() && buttonAt(rel()) == m_pressed)
                act(m_pressed);
            m_pressed = -1;
            return;
        }
        if (!w || !pointerHere())
            return;
        // A popup (a menu) over the bar gets the click.
        if (w->hasPopupAt(g_pInputManager->getMouseCoordsInternal()))
            return;
        info.cancelled = true;
        m_swallowed    = true;
        if (Desktop::focusState()->window() != w)
            Desktop::focusState()->fullWindowFocus(w, Desktop::FOCUS_REASON_CLICK);
        if (w->isFloating())
            Desktop::windowState()->raise(w);

        m_pressed = buttonAt(rel());
        if (m_pressed >= 0)
            return;
        const auto now = std::chrono::steady_clock::now();
        if (now - m_lastDown < std::chrono::milliseconds(400)) {
            m_lastDown = {};
            act(2);   // double-click: fill the screen, like the green button
            return;
        }
        m_lastDown    = now;
        m_dragPending = true;
        m_downAt      = g_pInputManager->getMouseCoordsInternal();
    }

    void act(int which) {
        auto w = m_window.lock();
        if (!w)
            return;
        if (which == 0)
            w->backend().close();
        else if (which == 1)
            Config::Supplementary::executor()->spawn("memora-shell minimize");
        else
            Config::Supplementary::executor()->spawn("memora-window fill");
    }

    PHLWINDOWREF                          m_window;
    CBox                                  m_assigned;
    CHyprSignalListener                   m_button, m_move;
    bool                                  m_hover = false, m_dragging = false, m_dragPending = false, m_swallowed = false, m_rightSwallowed = false;
    int                                   m_pressed = -1;
    Vector2D                              m_downAt;
    std::chrono::steady_clock::time_point m_lastDown;
    SP<Render::ITexture>                  m_symbols[3];
    float                                 m_symbolScale = 0;
    SP<Render::ITexture>                  m_titleTex;
    std::string                           m_title, m_titleFont;
    bool                                  m_titleActive = false, m_titleDark = true;
    int                                   m_titleW = 0;
};

std::vector<UP<IPassElement>> CMemoraBarPass::draw(Render::CRenderContext& ctx) {
    m_bar->render(ctx, ctx.m_data.pMonitor.lock(), m_a);
    return {};
}
std::optional<CBox> CMemoraBarPass::boundingBox(Render::CRenderContext& ctx) {
    return m_bar->globalBox().translate(-ctx.m_data.pMonitor->m_position).expand(10);
}

// Did this window ask the system to draw its title bar? What the app asked
// for counts, not the answer: Hyprland answers "server side" to everyone, and
// Chromium (which asks for client side) draws its own buttons anyway.
// Memora's own windows ask for server side (Qt does by default) but draw
// their own buttons (ui/WindowControls.qml), so they are left out.
static bool wantsSystemBar(PHLWINDOW w) {
    if (!w || !PROTO::xdgDecoration || w->backend().type() != Desktop::View::eBackendType::WINDOW_BACKEND_WAYLAND)
        return false;
    if (w->metadata().appID().starts_with("memora"))
        return false;
    const auto surface = w->backend().surface();
    if (!surface)
        return false;
    for (auto& [toplevelRes, deco] : PROTO::xdgDecoration->m_decorations) {
        if (!deco)
            continue;
        auto toplevel = CXDGToplevelResource::fromResource(toplevelRes);
        if (!toplevel)
            continue;
        auto owner = toplevel->m_owner.lock();
        if (owner && owner->m_surface.lock() == surface)
            return deco->mostRecentlyRequested == ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE;
    }
    return false;
}

// Which windows have a bar, for memora-window: it places them with room for it
// ($XDG_RUNTIME_DIR/memora-titlebars: "0xADDRESS HEIGHT" per line).
static void publishBars() {
    const char* run = getenv("XDG_RUNTIME_DIR");
    if (!run)
        return;
    const std::string path = std::string(run) + "/memora-titlebars";
    std::ofstream     f(path + ".new");
    for (auto& b : g_bars)
        if (auto bar = b.lock())
            if (auto w = bar->owner())
                f << std::format("0x{:x} {}\n", (uintptr_t)w.get(), BAR_H);
    f.close();
    std::rename((path + ".new").c_str(), path.c_str());
}

// `hyprctl memora-sizes`: each window's smallest and largest size and whether it
// is a dialog (has a parent), as JSON. memora-window and the shell use it to
// offer only the docking zones a window can really take.
static IPC::Socket1::SResponse sizesJSON(const IPC::Socket1::SRequest&) {
    std::string out = "[";
    bool        first = true;
    for (auto& w : Desktop::windowState()->windows()) {
        if (!w || !validMapped(w) || w->isHidden())
            continue;
        Vector2D mn{1, 1}, mx{0, 0};
        bool     parent = false;
        if (PROTO::xdgShell && w->backend().type() == Desktop::View::eBackendType::WINDOW_BACKEND_WAYLAND) {
            const auto surface = w->backend().surface();
            for (auto& tl : PROTO::xdgShell->m_toplevels) {
                if (!tl)
                    continue;
                auto owner = tl->m_owner.lock();
                if (!owner || owner->m_surface.lock() != surface)
                    continue;
                mn     = tl->layoutMinSize();
                mx     = tl->layoutMaxSize();
                parent = !!tl->m_parent.lock();
                break;
            }
        }
        out += std::format("{}{{\"address\":\"0x{:x}\",\"min\":[{},{}],\"max\":[{},{}],\"parent\":{}}}", first ? "" : ",", (uintptr_t)w.get(), (int)std::max(1.0, mn.x),
                           (int)std::max(1.0, mn.y), (int)mx.x, (int)mx.y, parent ? "true" : "false");
        first = false;
    }
    return IPC::Socket1::SResponse(out + "]");
}
static SP<IPC::Socket1::SCommand> g_sizesCmd;

static HANDLE              g_handle = nullptr;
static CHyprSignalListener g_open, g_title, g_active, g_tdown, g_tmotion, g_tup;

// Touch on a title bar Memora draws: tap a button, double-tap to fill the
// screen, or drag the window with the finger (the pointer follows the finger,
// so docking at the edges works as with the mouse).
namespace {
    WP<CMemoraBar>                        g_touchBar;
    int32_t                               g_touchID = -1, g_touchBtn = -1;
    bool                                  g_touchDragging = false;
    Vector2D                              g_touchAt;
    std::chrono::steady_clock::time_point g_lastTap;
    Vector2D touchPoint(const Vector2D& norm) {
        auto mon = Desktop::focusState()->monitor();
        return mon ? mon->m_position + norm * mon->m_size : norm;
    }
}
static void touchInit() {
    g_tdown = Event::bus()->m_events.input.touch.down.listen([](const ITouch::SDownEvent& e, Event::SCallbackInfo& info) {
        const auto p = touchPoint(e.pos);
        for (auto& b : g_bars) {
            auto bar = b.lock();
            if (!bar || !bar->touchHits(p))
                continue;
            info.cancelled = true;
            g_touchBar     = bar;
            g_touchID      = e.touchID;
            g_touchAt      = p;
            g_touchBtn     = bar->touchButton(p);
            g_touchDragging = false;
            if (auto w = bar->owner()) {
                Desktop::focusState()->fullWindowFocus(w, Desktop::FOCUS_REASON_CLICK);
                if (w->isFloating())
                    Desktop::windowState()->raise(w);
            }
            return;
        }
    });
    g_tmotion = Event::bus()->m_events.input.touch.motion.listen([](const ITouch::SMotionEvent& e, Event::SCallbackInfo& info) {
        if (e.touchID != g_touchID)
            return;
        info.cancelled = true;
        const auto p   = touchPoint(e.pos);
        auto       bar = g_touchBar.lock();
        if (!bar)
            return;
        if (!g_touchDragging && g_touchBtn < 0 && std::abs(p.x - g_touchAt.x) + std::abs(p.y - g_touchAt.y) > 8) {
            g_touchDragging = true;
            Pointer::mgr()->warpTo(g_touchAt);
            g_pInputManager->simulateMouseMovement();
            if (auto w = bar->owner())
                g_layoutManager->beginDragTarget(w->layoutTarget(), MBIND_MOVE);
            Config::Supplementary::executor()->spawn("memora-shell snap begin");
        }
        if (g_touchDragging) {
            Pointer::mgr()->warpTo(p);
            g_pInputManager->simulateMouseMovement();
        }
    });
    g_tup = Event::bus()->m_events.input.touch.up.listen([](const ITouch::SUpEvent& e, Event::SCallbackInfo& info) {
        if (e.touchID != g_touchID)
            return;
        info.cancelled = true;
        auto bar       = g_touchBar.lock();
        g_touchID      = -1;
        if (g_touchDragging) {
            g_layoutManager->endDragTarget();
            g_touchDragging = false;
            Config::Supplementary::executor()->spawn("memora-shell snap end");
            return;
        }
        if (!bar)
            return;
        if (g_touchBtn >= 0) {
            bar->touchAct(g_touchBtn);
            return;
        }
        const auto now = std::chrono::steady_clock::now();
        if (now - g_lastTap < std::chrono::milliseconds(400)) {
            g_lastTap = {};
            bar->touchAct(2);   // double tap: fill the screen
        } else
            g_lastTap = now;
    });
}

static void maybeAddBar(PHLWINDOW w) {
    if (!w || !wantsSystemBar(w))
        return;
    if (std::ranges::any_of(w->presentation().decorations(), [](const auto& d) { return d->getDisplayName() == "MemoraBar"; }))
        return;
    auto bar = makeShared<CMemoraBar>(w);
    g_bars.emplace_back(bar);
    HyprlandAPI::addWindowDecoration(g_handle, w, std::move(bar));
    publishBars();
}

static void forBar(PHLWINDOW w, auto&& fn) {
    for (auto& b : g_bars)
        if (auto bar = b.lock())
            for (auto& d : w->presentation().decorations())
                if (d.get() == bar.get())
                    fn(bar);
}

void memoraTitlebarInit(HANDLE handle) {
    g_handle = handle;
    touchInit();
    g_sizesCmd = HyprlandAPI::registerHyprCtlCommand(handle, IPC::Socket1::SCommand{.name = "memora-sizes", .match = IPC::Socket1::COMMAND_MATCH_EXACT, .handler = sizesJSON});
    g_open   = Event::bus()->m_events.window.open.listen([](PHLWINDOW w) { maybeAddBar(w); });
    g_title  = Event::bus()->m_events.window.title.listen([](PHLWINDOW w) { forBar(w, [](auto& bar) { bar->titleChanged(); }); });
    // Buttons and title change colour with focus: redraw every bar.
    g_active = Event::bus()->m_events.window.active.listen([](PHLWINDOW, Desktop::eFocusReason) {
        for (auto& b : g_bars)
            if (auto bar = b.lock())
                bar->damageEntire();
    });
    for (auto& w : Desktop::windowState()->windows())
        if (!w->isHidden() && validMapped(w))
            maybeAddBar(w);
}

void memoraTitlebarExit() {
    if (g_sizesCmd)
        HyprlandAPI::unregisterHyprCtlCommand(g_handle, g_sizesCmd);
    g_sizesCmd.reset();
    g_open.reset();
    g_title.reset();
    g_active.reset();
    g_tdown.reset();
    g_tmotion.reset();
    g_tup.reset();
    g_pHyprRenderer->context().m_pass.removeAllOfType("CMemoraBarPass");
    g_bars.clear();
    publishBars();
}
