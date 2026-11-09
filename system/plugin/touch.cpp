// memora-touch: what a touch screen needs from the compositor.
//  - The input mode: "touch" after a finger lands, "pointer" after the mouse or
//    trackpad is used. Only the change is told ("memorainput>>touch|pointer",
//    and $XDG_RUNTIME_DIR/memora-input), so the shell can make targets bigger
//    and show the on-screen keyboard only for touch. Keys are never looked at.
//  - Gestures, told to the shell as "memoragesture>>NAME":
//      from an edge (the first finger lands within EDGE px of it; such touches
//      don't reach apps): edge-bottom-short / edge-bottom-long, edge-top-left,
//      edge-top-right, edge-left, edge-right
//      three fingers: three-up, three-down, three-left, three-right
//      four fingers: pinch-in, pinch-out
// Built for Hyprland 0.57 together with minimize.cpp and titlebar.cpp (build.sh).
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/ipc/s2/S2.hpp>
#include <hyprland/src/devices/ITouch.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <unordered_map>

namespace {
    constexpr double EDGE = 8; // logical px from the screen edge

    struct STouch {
        Vector2D start, now;
    };
    std::unordered_map<int32_t, STouch> g_touches;
    int                                 g_maxFingers = 0;
    bool                                g_edge       = false; // this gesture began at an edge (swallowed)
    std::string                         g_edgeSide;
    Vector2D                            g_monPos, g_monSize{1, 1};
    bool                                g_touchMode = false;
    std::chrono::steady_clock::time_point g_lastTouch;
    CHyprSignalListener                 g_down, g_up, g_motion, g_cancel, g_mouseMove, g_mouseButton;

    void post(const std::string& name, const std::string& data) {
        IPC::Socket2::sock()->postEvent({name, data});
    }

    void setMode(bool touch) {
        if (touch == g_touchMode)
            return;
        g_touchMode = touch;
        post("memorainput", touch ? "touch" : "pointer");
        if (const char* run = getenv("XDG_RUNTIME_DIR")) {
            const std::string path = std::string(run) + "/memora-input";
            std::ofstream     f(path + ".new");
            f << (touch ? "touch" : "pointer") << "\n";
            f.close();
            std::rename((path + ".new").c_str(), path.c_str());
        }
    }

    double spread(bool atStart) {
        Vector2D c{0, 0};
        for (auto& [id, t] : g_touches)
            c = c + (atStart ? t.start : t.now);
        c = c / std::max<size_t>(1, g_touches.size());
        double d = 0;
        for (auto& [id, t] : g_touches) {
            const auto p = (atStart ? t.start : t.now) - c;
            d += std::hypot(p.x, p.y);
        }
        return d / std::max<size_t>(1, g_touches.size());
    }

    void finish() {
        Vector2D d{0, 0};
        for (auto& [id, t] : g_touches)
            d = d + (t.now - t.start);
        d = d / std::max<size_t>(1, g_touches.size());
        std::string name;
        if (g_edge) {
            const auto& t = g_touches.begin()->second;
            if (g_edgeSide == "bottom" && d.y < -30)
                name = -d.y > g_monSize.y * 0.2 ? "edge-bottom-long" : "edge-bottom-short";
            else if (g_edgeSide == "top" && d.y > 40)
                name = t.start.x - g_monPos.x < g_monSize.x / 2 ? "edge-top-left" : "edge-top-right";
            else if (g_edgeSide == "left" && d.x > 60)
                name = "edge-left";
            else if (g_edgeSide == "right" && d.x < -60)
                name = "edge-right";
        } else if (g_maxFingers == 3) {
            if (std::abs(d.x) > std::abs(d.y) && std::abs(d.x) > 80)
                name = d.x < 0 ? "three-left" : "three-right";
            else if (std::abs(d.y) > 80)
                name = d.y < 0 ? "three-up" : "three-down";
        } else if (g_maxFingers >= 4) {
            const double a = spread(true), b = spread(false);
            if (a > 1 && b / a < 0.7)
                name = "pinch-in";
            else if (a > 1 && b / a > 1.4)
                name = "pinch-out";
        }
        if (!name.empty())
            post("memoragesture", name);
    }
}

void memoraTouchInit(HANDLE) {
    g_down = Event::bus()->m_events.input.touch.down.listen([](const ITouch::SDownEvent& e, Event::SCallbackInfo& info) {
        g_lastTouch = std::chrono::steady_clock::now();
        setMode(true);
        auto mon = Desktop::focusState()->monitor();
        if (g_touches.empty()) {
            g_maxFingers = 0;
            g_edge       = false;
            if (mon) {
                g_monPos  = mon->m_position;
                g_monSize = mon->m_size;
            }
        }
        const Vector2D p = g_monPos + e.pos * g_monSize;
        g_touches[e.touchID] = {p, p};
        g_maxFingers         = std::max<int>(g_maxFingers, g_touches.size());
        if (g_touches.size() == 1) {
            const auto rel = p - g_monPos;
            if (rel.y >= g_monSize.y - EDGE)
                g_edgeSide = "bottom";
            else if (rel.y <= EDGE)
                g_edgeSide = "top";
            else if (rel.x <= EDGE)
                g_edgeSide = "left";
            else if (rel.x >= g_monSize.x - EDGE)
                g_edgeSide = "right";
            else
                g_edgeSide.clear();
            g_edge = !g_edgeSide.empty();
        }
        if (g_edge)
            info.cancelled = true;
    });
    g_motion = Event::bus()->m_events.input.touch.motion.listen([](const ITouch::SMotionEvent& e, Event::SCallbackInfo& info) {
        g_lastTouch = std::chrono::steady_clock::now();
        auto it     = g_touches.find(e.touchID);
        if (it != g_touches.end())
            it->second.now = g_monPos + e.pos * g_monSize;
        if (g_edge)
            info.cancelled = true;
    });
    g_up = Event::bus()->m_events.input.touch.up.listen([](const ITouch::SUpEvent& e, Event::SCallbackInfo& info) {
        g_lastTouch = std::chrono::steady_clock::now();
        if (g_edge)
            info.cancelled = true;
        if (!g_touches.contains(e.touchID))
            return;
        if (g_touches.size() == 1)
            finish();
        g_touches.erase(e.touchID);
    });
    g_cancel = Event::bus()->m_events.input.touch.cancel.listen([](const ITouch::SCancelEvent& e, Event::SCallbackInfo&) { g_touches.erase(e.touchID); });
    // The mouse or trackpad used again (not the pointer moved by a touch): pointer mode.
    auto pointerUsed = []() {
        if (std::chrono::steady_clock::now() - g_lastTouch > std::chrono::milliseconds(600))
            setMode(false);
    };
    g_mouseMove   = Event::bus()->m_events.input.mouse.move.listen([pointerUsed](const auto&, auto&) { pointerUsed(); });
    g_mouseButton = Event::bus()->m_events.input.mouse.button.listen([pointerUsed](const auto&, auto&) { pointerUsed(); });
}

void memoraTouchExit() {
    g_down.reset();
    g_up.reset();
    g_motion.reset();
    g_cancel.reset();
    g_mouseMove.reset();
    g_mouseButton.reset();
    g_touches.clear();
}
