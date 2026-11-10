// memora-glass: liquid glass for the shell's panels (Dock, menu bar, Control
// Center, notifications, Spotlight…), drawn by the compositor because only it
// sees what is behind them. Under each glass shape it draws what is behind,
// frosted (Hyprland's own blur, as set in System Settings > Appearance), with
// the rim of the shape bent inwards like the edge of a lens and split a little
// into colours, after ybouane/liquidglass (MIT). The shell then draws its tint
// and the light on the rim on top (shell/ui/glass.frag). No shadow.
// Like Apple's glass it adapts to what is behind: in the dark look a bright
// background is dimmed under the light text, in the light look a dark one is
// lifted under the dark text; over dark or colourful things it stays clear.
//
// The shell tells where its glass is over a local socket,
// $XDG_RUNTIME_DIR/memora-glass.sock, one line per change:
//   R <id> <namespace> <monitor> <surface w> <surface h> <x> <y> <w> <h> <radius> <bevel> <opacity>
//   D <id>          (gone)
//   (after the opacity: L for the layer itself, P for a menu hanging from it,
//   then the size is the menu's and the box is in the menu)
// in logical px, relative to the layer surface (shell/core/GlassSync.qml).
// Layers with glass are not blurred by Hyprland any more: this draws it.
// Built for Hyprland 0.57 together with minimize.cpp (build.sh).
#define WLR_USE_UNSTABLE
#include <algorithm>
#include <any>
#include <cmath>
#include <cstdio>
#include <format>
#include <functional>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <unordered_map>
#include <variant>
#include <vector>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <fcntl.h>
#include <fstream>
#include <sys/stat.h>

// The pass keeps its elements to itself.
#define private public
#include <hyprland/src/render/pass/Pass.hpp>
#undef private

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/plugins/HookSystem.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/ipc/s1/S1.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>
#include <hyprland/src/render/pass/SurfacePassElement.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Shader.hpp>
#include <hyprland/src/render/Framebuffer.hpp>
#include <hyprland/src/render/Texture.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/protocols/LayerShell.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/state/MonitorState.hpp>

using namespace Render;
using namespace Render::GL;

namespace {
    struct SGlass {
        std::string ns, monitor;
        Vector2D    surface;      // the layer surface's size, to tell layers with the same namespace apart
        CBox        box;          // in the surface
        float       radius = 0, bevel = 0, alpha = 1;
        bool        popup = false;    // in a menu hanging from the layer, not the layer itself
    };
    std::unordered_map<std::string, SGlass> g_glass;

    // Light or dark, as Memora's appearance (memora-theme writes it).
    bool dark() {
        static std::string path = std::string(getenv("HOME") ? getenv("HOME") : "") + "/.config/memora/theme";
        static time_t      seen = -1;
        static bool        val  = true;
        struct stat        st {};
        if (stat(path.c_str(), &st) == 0 && st.st_mtime != seen) {
            seen = st.st_mtime;
            std::ifstream f(path);
            std::string   v;
            f >> v;
            val = v.find("light") == std::string::npos;
        }
        return val;
    }
    uint64_t                                g_draws = 0, g_hooked = 0;

    // ------------------------------------------------------------------ shader

    const char* VERT = R"(#version 300 es
uniform mat3 proj;
in vec2 pos;
in vec2 texcoord;
out vec2 v_texcoord;
void main() {
    gl_Position = vec4(proj * vec3(pos, 1.0), 1.0);
    v_texcoord = texcoord;
})";

    const char* FRAG = R"(#version 300 es
precision highp float;
in vec2 v_texcoord;
uniform sampler2D texSharp;
uniform sampler2D texBlur;
uniform vec2 fbSize;
uniform vec2 size;
uniform float pad;
uniform float radius;
uniform float zRadius;
uniform float refraction;
uniform float chroma;
uniform float alpha;
uniform float darkMode;
layout(location = 0) out vec4 fragColor;

float rrSDF(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}
float bevelHeight(float d, float zR) {
    if (d <= 0.0) return 0.0;
    if (d >= zR) return zR;
    return sqrt(d * (2.0 * zR - d));
}

void main() {
    vec2 half_ = size * 0.5;
    vec2 p = (v_texcoord - 0.5) * (size + 2.0 * pad);
    // From a step in the shape to a step on screen (the monitor may be rotated).
    mat2 toScreen = inverse(mat2(dFdx(p), dFdy(p)));

    float r = min(radius, min(half_.x, half_.y));
    float sdf = rrSDF(p, half_, r);
    // The same soft edge as the shell's (shell/ui/glass.frag), at the same
    // place: wider, it shows as a second, untinted outline.
    float mask = 1.0 - smoothstep(-1.0, 0.5, sdf);
    if (mask <= 0.0) discard;

    float maxD = min(half_.x, half_.y);
    float inside = -sdf;
    float edge = smoothstep(maxD * 0.35, 0.0, inside);

    float zR = max(1.0, min(zRadius, maxD));
    // A wide step smooths the rim's slope (it is vertical at the very edge).
    float e = 3.0;
    float hC = bevelHeight(inside, zR);
    float hR = bevelHeight(-rrSDF(p + vec2(e, 0.0), half_, r), zR);
    float hL = bevelHeight(-rrSDF(p - vec2(e, 0.0), half_, r), zR);
    float hD = bevelHeight(-rrSDF(p + vec2(0.0, e), half_, r), zR);
    float hU = bevelHeight(-rrSDF(p - vec2(0.0, e), half_, r), zR);
    vec2 hGrad = vec2(hR - hL, hD - hU) / (2.0 * e);
    vec3 N = normalize(vec3(-hGrad, 1.0));
    float depth = smoothstep(0.0, zR, inside);

    // Biconvex lens: light bends at both faces of the rim.
    float refrPow = 1.0 - 1.0 / 1.5;
    float thickNorm = (hC * 2.0) / max(zR * 2.0, 1.0);
    vec2 bend = hGrad * refrPow;
    vec2 refrPx = (bend * 2.0 + bend * thickNorm * 0.5) * refraction * 30.0;
    refrPx += (-p / max(half_, vec2(1.0))) * refraction * 4.0 * depth;
    // Never more than the rim is wide: squeezing more into the last pixels
    // shows as stripes.
    float refrLen = length(refrPx);
    float refrMax = zR * 0.8;
    if (refrLen > refrMax) refrPx *= refrMax / refrLen;
    float caS = chroma * 36.0 * (edge * 0.7 + 0.3);

    vec2 base = (gl_FragCoord.xy + toScreen * refrPx) / fbSize;
    vec2 ca = (toScreen * (N.xy * caS)) / fbSize;
    vec2 lo = vec2(0.5) / fbSize, hi = vec2(1.0) - lo;
    vec2 uR = clamp(base + ca, lo, hi), uG = clamp(base, lo, hi), uB = clamp(base - ca, lo, hi);
    vec3 sharp = vec3(texture(texSharp, uR).r, texture(texSharp, uG).g, texture(texSharp, uB).b);
    vec3 blur  = vec3(texture(texBlur, uR).r, texture(texBlur, uG).g, texture(texBlur, uB).b);
    // Frosted all over, as Apple's: the rim bends the picture, it isn't
    // clearer (a clear ring reads as a second frame). Only a little, fading in.
    float rimSharp = smoothstep(zR, 0.0, inside) * smoothstep(0.0, 4.0, inside) * 0.3;
    vec3 col = mix(blur, sharp, rimSharp);
    col *= 1.0 + 0.06 * depth;

    // Adaptive, as Apple's "regular" glass: how bright is what is behind, here
    // and across the whole shape (so a menu over a white page reads as one sheet)?
    const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
    float here = dot(texture(texBlur, uG).rgb, LUMA);
    float whole = 0.0;
    for (int i = 0; i < 5; i++) {
        vec2 at = i == 0 ? vec2(0.0) : vec2(i == 1 ? -0.5 : i == 2 ? 0.5 : 0.0, i == 3 ? -0.5 : i == 4 ? 0.5 : 0.0) * half_;
        whole += dot(texture(texBlur, clamp((gl_FragCoord.xy + toScreen * (at - p)) / fbSize, lo, hi)).rgb, LUMA);
    }
    float L = mix(here, whole / 5.0, 0.6);
    if (darkMode > 0.5) {
        // Light text: a bright background is dimmed until it reads, a dark one left clear.
        col *= 1.0 - smoothstep(0.3, 0.95, L) * 0.65;
    } else {
        // Dark text: a dark background is lifted towards white.
        col = mix(col, vec3(1.0), smoothstep(0.6, 0.1, L) * 0.62);
    }
    fragColor = vec4(col, 1.0) * mask * alpha;
})";

    SP<CShader> g_shader;
    bool        g_shaderFailed = false;
    struct {
        GLint darkMode = -1;
        GLint sharp = -1, blur = -1, fbSize = -1, size = -1, pad = -1, radius = -1, zRadius = -1, refraction = -1, chroma = -1, alpha = -1;
    } U;

    bool ensureShader() {
        if (g_shader)
            return true;
        if (g_shaderFailed)
            return false;
        auto s = makeShared<CShader>();
        if (!s->createProgram(VERT, FRAG, true, false)) {
            g_shaderFailed = true;
            return false;
        }
        const auto P = s->program();
        U.sharp      = glGetUniformLocation(P, "texSharp");
        U.blur       = glGetUniformLocation(P, "texBlur");
        U.fbSize     = glGetUniformLocation(P, "fbSize");
        U.size       = glGetUniformLocation(P, "size");
        U.pad        = glGetUniformLocation(P, "pad");
        U.darkMode   = glGetUniformLocation(P, "darkMode");
        U.radius     = glGetUniformLocation(P, "radius");
        U.zRadius    = glGetUniformLocation(P, "zRadius");
        U.refraction = glGetUniformLocation(P, "refraction");
        U.chroma     = glGetUniformLocation(P, "chroma");
        U.alpha      = glGetUniformLocation(P, "alpha");
        g_shader     = s;
        return true;
    }

    // A copy of what is behind, per monitor (a framebuffer can't be read while drawn into).
    std::unordered_map<std::string, SP<IFramebuffer>> g_copies;

    // ------------------------------------------------------------- the shapes

    bool belongs(const SGlass& g, PHLLS ls, PHLMONITOR mon) {
        if (g.popup || !ls || !mon || ls->m_namespace != g.ns || mon->m_name != g.monitor)
            return false;
        const auto S = ls->size(Desktop::View::IGeometric::GEOMETRIC_GOAL);
        return std::abs(S.x - g.surface.x) < 1.5 && std::abs(S.y - g.surface.y) < 1.5;
    }

    std::vector<const SGlass*> glassOf(PHLLS ls, PHLMONITOR mon) {
        std::vector<const SGlass*> out;
        for (auto& [_, g] : g_glass)
            if (g.alpha > 0.01 && belongs(g, ls, mon))
                out.push_back(&g);
        return out;
    }

    // Redraw where a shape is (or was).
    void damage(const SGlass& g) {
        // A menu: where it is isn't known here; menus change seldom.
        if (g.popup) {
            for (auto& mon : State::monitorState()->monitors())
                if (mon && mon->m_name == g.monitor)
                    g_pHyprRenderer->damageMonitor(mon);
            return;
        }
        for (auto& mon : State::monitorState()->monitors()) {
            if (!mon || mon->m_name != g.monitor)
                continue;
            for (auto& layer : mon->m_layerSurfaceLayers)
                for (auto& ref : layer) {
                    auto ls = ref.lock();
                    if (!ls || !belongs(g, ls, mon))
                        continue;
                    CBox b = g.box;
                    b.translate(ls->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT));
                    g_pHyprRenderer->damageBox(b.expand(4));
                }
        }
    }
}

// ------------------------------------------------------------------ drawing

class CMemoraGlassPass : public IPassElement {
  public:
    CMemoraGlassPass(PHLLS ls, PHLMONITOR mon, std::vector<SGlass> shapes, Vector2D origin, float fade) :
        m_ls(ls), m_mon(mon), m_shapes(std::move(shapes)), m_origin(origin), m_fade(fade) {}

    bool                needsLiveBlur(CRenderContext&) override { return true; }
    bool                needsPrecomputeBlur(CRenderContext&) override { return false; }
    const char*         passName() override { return "CMemoraGlassPass"; }
    ePassElementType    type() override { return EK_CUSTOM; }
    bool                disableSimplification(CRenderContext&) override { return false; }

    std::optional<CBox> boundingBox(CRenderContext&) override {
        CBox all;
        bool first = true;
        for (auto& g : m_shapes) {
            CBox b = g.box;
            b.translate(m_origin);
            if (first)
                all = b;
            else {
                const double x1 = std::min(all.x, b.x), y1 = std::min(all.y, b.y);
                const double x2 = std::max(all.x + all.w, b.x + b.w), y2 = std::max(all.y + all.h, b.y + b.h);
                all = {x1, y1, x2 - x1, y2 - y1};
            }
            first = false;
        }
        return all.expand(3);   // the soft edge reaches a little outside
    }

    std::vector<UP<IPassElement>> draw(CRenderContext& ctx) override {
        auto mon = ctx.m_data.pMonitor.lock();
        auto* gl = g_pHyprOpenGL.get();
        if (!mon || !gl || m_shapes.empty() || ctx.m_data.damage.empty() || !ensureShader())
            return {};
        const auto target = ctx.m_data.currentFB;
        if (!target || !target->getTexture())
            return {};

        g_draws++;
        // 1. What is behind, sharp: copy the frame drawn so far.
        auto& copy = g_copies[mon->m_name];
        if (!copy)
            copy = g_pHyprRenderer->createFB("memora-glass");
        if (!copy)
            return {};
        if (!copy->isAllocated() || copy->m_size != target->m_size)
            copy->alloc(target->m_size.x, target->m_size.y, target->m_drmFormat == DRM_FORMAT_INVALID ? DRM_FORMAT_ARGB8888 : target->m_drmFormat);
        {
            auto guard = g_pHyprRenderer->bindTempFB(ctx, copy);
            auto state = ctx.saveDrawState();
            ctx.m_data.renderModif        = {};
            ctx.m_data.useNearestNeighbor = true;
            gl->blend(false);
            gl->renderOffToMain(ctx, target);
            gl->blend(true);
        }

        // 2. Frosted, by Hyprland's blur (the strength set in Appearance).
        CBox pattern = *boundingBox(ctx);
        pattern.scale(mon->m_scale).round();
        auto blurred = g_pHyprRenderer->blurMainFramebuffer(ctx, m_fade, ctx.m_data.damage, {.patternBox = pattern});
        auto blurTex = blurred ? blurred->getTexture() : copy->getTexture();

        // 3. The lens.
        gl->blend(true);
        gl->useShader(g_shader);
        gl->setActiveTexture(GL_TEXTURE0);
        copy->getTexture()->bind();
        gl->setActiveTexture(GL_TEXTURE1);
        blurTex->bind();
        glUniform1i(U.sharp, 0);
        glUniform1i(U.blur, 1);
        glUniform2f(U.fbSize, target->m_size.x, target->m_size.y);
        glUniform1f(U.refraction, 0.69F);
        glUniform1f(U.chroma, 0.05F);
        glUniform1f(U.darkMode, dark() ? 1.F : 0.F);

        const double PAD = 2.0;   // fb px around the shape
        CRegion      stale;
        for (auto& g : m_shapes) {
            // Not rounded: the shell draws its part at the same fractional place.
            CBox box = g.box;
            box.translate(m_origin);
            box.scale(mon->m_scale);
            if (box.w < 2 || box.h < 2)
                continue;
            CBox quad = box.copy().expand(PAD);
            const auto M = g_pHyprRenderer->projectBoxToTarget(ctx, quad);
            g_shader->setUniformMatrix3fv(SHADER_PROJ, 1, GL_TRUE, M.getMatrix());
            glUniform2f(U.size, box.w, box.h);
            glUniform1f(U.pad, PAD);
            glUniform1f(U.radius, g.radius * mon->m_scale);
            glUniform1f(U.zRadius, g.bevel * mon->m_scale);
            glUniform1f(U.alpha, std::clamp(g.alpha * m_fade, 0.F, 1.F));
            glBindVertexArray(g_shader->getUniformLocation(SHADER_SHADER_VAO));
            CBox    area = quad.copy().round();
            CRegion here = ctx.m_data.damage.copy().intersect(area);
            // Outside this frame's damage the frame still holds the last one,
            // glass included: the lens must not bend that in. Redraw all of it next.
            if (!CRegion{area}.subtract(ctx.m_data.damage).empty())
                stale.add(g.box.copy().translate(m_origin + mon->m_position).expand(PAD + 2));
            here.forEachRect([&](const auto& R) {
                gl->scissor(ctx, &R, ctx.m_data.transformDamage);
                glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
            });
        }
        gl->scissor(ctx, nullptr);
        glBindVertexArray(0);
        if (!stale.empty())
            stale.forEachRect([](const auto& R) { g_pHyprRenderer->damageBox(CBox(R.x1, R.y1, R.x2 - R.x1, R.y2 - R.y1)); });
        blurTex->unbind();
        gl->setActiveTexture(GL_TEXTURE0);
        copy->getTexture()->unbind();
        return {};
    }

  private:
    PHLLSREF            m_ls;
    PHLMONITORREF       m_mon;
    std::vector<SGlass> m_shapes;
    Vector2D            m_origin; // the layer, monitor-local logical
    float               m_fade = 1;
};

// The layer is drawn: its glass first, then the layer itself, without
// Hyprland's blur (the glass is the frost now).
typedef void (*origRenderLayer)(void*, CRenderContext&, PHLLS, PHLMONITOR, const Time::steady_tp&, bool, bool, bool);
static CFunctionHook* g_renderLayerHook = nullptr;
static HANDLE         g_handle          = nullptr;

// The menus hanging from a layer: each gets its glass just before it is drawn.
static void addPopupGlass(CRenderContext& ctx, PHLLS ls, PHLMONITOR mon, size_t from) {
    auto& pass = IHyprRenderer::currentPass(ctx);
    for (size_t i = from; i < pass.m_passElements.size(); i++) {
        auto& el = pass.m_passElements[i].element;
        if (!el || el->type() != EK_SURFACE)
            continue;
        auto* s = static_cast<CSurfacePassElement*>(el.get());
        if (s->m_data.pLS != ls || !s->m_data.popup || !s->m_data.surface)
            continue;
        const auto          SIZE = s->m_data.surface->m_current.size;
        std::vector<SGlass> shapes;
        for (auto& [_, g] : g_glass)
            if (g.popup && g.alpha > 0.01 && g.ns == ls->m_namespace && g.monitor == mon->m_name && std::abs(g.surface.x - SIZE.x) < 1.5 &&
                std::abs(g.surface.y - SIZE.y) < 1.5)
                shapes.push_back(g);
        if (shapes.empty())
            continue;
        s->m_data.blur = false;
        s->m_data.discardMode &= ~DISCARD_ALPHA;
        const auto origin = s->m_data.pos + s->m_data.localPos - mon->m_position;
        const auto fade   = s->m_data.fadeAlpha;
        g_hooked++;
        pass.m_passElements.insert(pass.m_passElements.begin() + i, {.element = makeUnique<CMemoraGlassPass>(ls, mon, std::move(shapes), origin, fade)});
        i++;   // past the menu itself
    }
}

static void hkRenderLayer(void* thisptr, CRenderContext& ctx, PHLLS ls, PHLMONITOR mon, const Time::steady_tp& time, bool popups, bool lockscreen, bool workspaceScene) {
    auto orig = (origRenderLayer)g_renderLayerHook->m_original;
    // Nothing is behind the desktop layers.
    if (ctx.m_renderingSnapshot || !ls || !mon || !ls->m_namespace.starts_with("memora-") || ls->m_layer <= ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM) {
        orig(thisptr, ctx, ls, mon, time, popups, lockscreen, workspaceScene);
        return;
    }
    auto&      pass   = IHyprRenderer::currentPass(ctx);
    const auto before = pass.m_passElements.size();
    if (popups) {
        orig(thisptr, ctx, ls, mon, time, popups, lockscreen, workspaceScene);
        addPopupGlass(ctx, ls, mon, before);
        return;
    }
    const auto shapes = glassOf(ls, mon);
    if (shapes.empty()) {
        orig(thisptr, ctx, ls, mon, time, popups, lockscreen, workspaceScene);
        return;
    }
    g_hooked++;
    std::vector<SGlass> copy;
    for (auto* g : shapes)
        copy.push_back(*g);
    const auto origin = ls->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT) - mon->m_position;
    const auto fade   = ls->alpha()[Desktop::View::LS_ALPHA_FADE]->value();

    // Not drawn when nothing would be (orig checks the same).
    if (ls->mapped() && ls->alphaNonZero())
        IHyprRenderer::addPassElement(ctx, makeUnique<CMemoraGlassPass>(ls, mon, std::move(copy), origin, fade));
    orig(thisptr, ctx, ls, mon, time, popups, lockscreen, workspaceScene);
    for (size_t i = before; i < pass.m_passElements.size(); i++) {
        auto& el = pass.m_passElements[i].element;
        if (!el || el->type() != EK_SURFACE)
            continue;
        auto* s = static_cast<CSurfacePassElement*>(el.get());
        if (s->m_data.pLS != ls || s->m_data.popup)
            continue;
        s->m_data.blur = false;
        s->m_data.discardMode &= ~DISCARD_ALPHA;
    }
}

// ------------------------------------------------------------------- socket

namespace {
    int                                          g_listenFd = -1;
    wl_event_source*                             g_listenSrc = nullptr;
    struct SClient {
        int              fd  = -1;
        wl_event_source* src = nullptr;
        std::string      buf;
        std::vector<std::string> ids;
    };
    std::unordered_map<int, UP<SClient>> g_clients;

    void forget(SClient& c) {
        for (auto& id : c.ids) {
            auto it = g_glass.find(id);
            if (it != g_glass.end()) {
                damage(it->second);
                g_glass.erase(it);
            }
        }
        c.ids.clear();
    }

    void handleLine(SClient& c, const std::string& line) {
        std::istringstream in(line);
        std::string        op, id;
        in >> op >> id;
        if (id.empty())
            return;
        id = std::format("{}:{}", c.fd, id);
        if (op == "D") {
            auto it = g_glass.find(id);
            if (it != g_glass.end()) {
                damage(it->second);
                g_glass.erase(it);
            }
            return;
        }
        if (op != "R")
            return;
        SGlass g;
        double sw, sh, x, y, w, h;
        in >> g.ns >> g.monitor >> sw >> sh >> x >> y >> w >> h >> g.radius >> g.bevel >> g.alpha;
        if (in.fail())
            return;
        std::string kind;
        in >> kind;
        g.popup = kind == "P";
        g.surface = {sw, sh};
        g.box     = {x, y, w, h};
        auto it   = g_glass.find(id);
        if (it != g_glass.end())
            damage(it->second);
        else
            c.ids.push_back(id);
        g_glass[id] = g;
        damage(g);
    }

    int onClient(int fd, uint32_t mask, void*) {
        auto it = g_clients.find(fd);
        if (it == g_clients.end())
            return 0;
        auto& c = *it->second;
        if (!(mask & (WL_EVENT_HANGUP | WL_EVENT_ERROR))) {
            char buf[4096];
            for (;;) {
                const auto n = read(fd, buf, sizeof(buf));
                if (n > 0) {
                    c.buf.append(buf, n);
                    continue;
                }
                if (n == 0)
                    mask |= WL_EVENT_HANGUP;
                break;
            }
            size_t nl;
            while ((nl = c.buf.find('\n')) != std::string::npos) {
                handleLine(c, c.buf.substr(0, nl));
                c.buf.erase(0, nl + 1);
            }
            if (c.buf.size() > 65536)
                c.buf.clear();
        }
        if (mask & (WL_EVENT_HANGUP | WL_EVENT_ERROR)) {
            forget(c);
            wl_event_source_remove(c.src);
            close(fd);
            g_clients.erase(it);
        }
        return 0;
    }

    int onAccept(int fd, uint32_t, void*) {
        const int cfd = accept4(fd, nullptr, nullptr, SOCK_NONBLOCK | SOCK_CLOEXEC);
        if (cfd < 0)
            return 0;
        auto c  = makeUnique<SClient>();
        c->fd   = cfd;
        c->src  = wl_event_loop_add_fd(g_pCompositor->m_wlEventLoop, cfd, WL_EVENT_READABLE, onClient, nullptr);
        g_clients[cfd] = std::move(c);
        return 0;
    }

    std::string socketPath() {
        const char* run = getenv("XDG_RUNTIME_DIR");
        return std::string(run ? run : "/tmp") + "/memora-glass.sock";
    }
}

// `hyprctl memora-glass`: the glass shapes the shell has told, and how often they were drawn.
static IPC::Socket1::SResponse glassInfo(const IPC::Socket1::SRequest&) {
    std::string out = std::format("layers with glass drawn: {}, glass passes drawn: {}, shader: {}\n", g_hooked, g_draws, g_shader ? "ok" : (g_shaderFailed ? "FAILED" : "not yet"));
    for (auto& [id, g] : g_glass)
        out += std::format("{} {} {} surface {}x{} box {} {} {} {} r {} bevel {} a {}\n", id, g.ns, g.monitor, g.surface.x, g.surface.y, g.box.x, g.box.y, g.box.w, g.box.h, g.radius,
                           g.bevel, g.alpha);
    return IPC::Socket1::SResponse(out);
}
static SP<IPC::Socket1::SCommand> g_infoCmd;

void memoraGlassInit(HANDLE handle) {
    g_infoCmd = HyprlandAPI::registerHyprCtlCommand(handle, IPC::Socket1::SCommand{.name = "memora-glass", .match = IPC::Socket1::COMMAND_MATCH_EXACT, .handler = glassInfo});
    g_handle  = handle;
    // The hook first: without it there is nothing to draw with.
    for (auto& fn : HyprlandAPI::findFunctionsByName(handle, "renderLayer")) {
        if (fn.demangled.find("IHyprRenderer::renderLayer") == std::string::npos)
            continue;
        g_renderLayerHook = HyprlandAPI::createFunctionHook(handle, fn.address, (void*)&hkRenderLayer);
        break;
    }
    if (!g_renderLayerHook || !g_renderLayerHook->hook()) {
        HyprlandAPI::addNotification(handle, "[memora] liquid glass: could not hook the renderer", CHyprColor{1.0, 0.4, 0.3, 1.0}, 5000);
        return;
    }

    const auto path = socketPath();
    unlink(path.c_str());
    g_listenFd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (g_listenFd < 0)
        return;
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", path.c_str());
    if (bind(g_listenFd, (sockaddr*)&addr, sizeof(addr)) < 0 || listen(g_listenFd, 4) < 0) {
        close(g_listenFd);
        g_listenFd = -1;
        return;
    }
    g_listenSrc = wl_event_loop_add_fd(g_pCompositor->m_wlEventLoop, g_listenFd, WL_EVENT_READABLE, onAccept, nullptr);
}

void memoraGlassExit() {
    if (g_infoCmd)
        HyprlandAPI::unregisterHyprCtlCommand(g_handle, g_infoCmd);
    g_infoCmd.reset();
    for (auto& [fd, c] : g_clients) {
        if (c->src)
            wl_event_source_remove(c->src);
        close(fd);
    }
    g_clients.clear();
    if (g_listenSrc)
        wl_event_source_remove(g_listenSrc);
    g_listenSrc = nullptr;
    if (g_listenFd >= 0) {
        close(g_listenFd);
        unlink(socketPath().c_str());
    }
    g_listenFd = -1;
    g_glass.clear();
    g_copies.clear();
    g_shader.reset();
    if (g_pHyprRenderer)
        IHyprRenderer::currentPass(g_pHyprRenderer->context()).removeAllOfType("CMemoraGlassPass");
}
