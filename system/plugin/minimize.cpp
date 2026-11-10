// memora-minimize: Hyprland ignores the minimize button of apps (a client's
// minimize request). This plugin turns that request into the IPC event
// "minimized>>ADDRESS,1", which the Memora shell answers by putting the window
// in the Dock.
// It also reports when Super or Alt is let go (and when Super goes down, for the
// shortcuts sheet) ("memorakeyup>>super" / "alt"):
// Hyprland keeps that to itself after a shortcut, and the app switcher
// (Super+Tab, Alt+Tab) needs it to finish switching. No other key is reported. Built for Hyprland 0.57 (window backends); build.sh rebuilds it
// after every Hyprland update.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowBackend.hpp>
#include <hyprland/src/ipc/s2/S2.hpp>
#include <format>
#include <unordered_map>

// titlebar.cpp: Mac-like title bars for apps that leave their frame to the system.
void memoraTitlebarInit(HANDLE handle);
void memoraTitlebarExit();
// touch.cpp: input mode (touch or pointer) and touch-screen gestures.
void memoraTouchInit(HANDLE handle);
void memoraTouchExit();

static HANDLE                                         PHANDLE = nullptr;
static CHyprSignalListener                            g_open, g_close, g_key, g_button;
static std::unordered_map<void*, CHyprSignalListener> g_state;

static void watch(PHLWINDOW w) {
    PHLWINDOWREF ref = w;
    g_state[w.get()] = w->backend().m_events.stateRequest.listen([ref](const Desktop::View::SBackendStateRequest& req) {
        auto win = ref.lock();
        if (win && req.minimized.value_or(false))
            IPC::Socket2::sock()->postEvent({"minimized", std::format("{:x},1", (uintptr_t)win.get())});
    });
}

// Super is down; something else was used with it since (a key, a mouse button:
// Super+drag moves a window, so that's not "Super held on its own").
static bool superDown = false, chord = false;
static void chordWithSuper() {
    if (superDown && !chord) {
        chord = true;
        IPC::Socket2::sock()->postEvent({"memorachord", "1"});
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;
    g_open  = Event::bus()->m_events.window.open.listen([](PHLWINDOW w) { watch(w); });
    g_close = Event::bus()->m_events.window.close.listen([](PHLWINDOW w) { g_state.erase(w.get()); });
    g_key   = Event::bus()->m_events.input.keyboard.key.listen([](const auto& ev, auto&) {
        // Super held on its own for a moment shows the shortcuts (the shell
        // times it): "memorakeydown>>super" when it goes down, "memorachord"
        // once if any other key is pressed meanwhile (which key is not told).
        if (ev.state == WL_KEYBOARD_KEY_STATE_PRESSED) {
            if (ev.keycode == 125 || ev.keycode == 126) {
                if (!superDown)
                    IPC::Socket2::sock()->postEvent({"memorakeydown", "super"});
                superDown = true;
                chord     = false;
            } else
                chordWithSuper();
            return;
        }
        if (ev.state != WL_KEYBOARD_KEY_STATE_RELEASED)
            return;
        if (ev.keycode == 125 || ev.keycode == 126)
            superDown = false;
        // evdev codes: 125/126 Super, 56/100 Alt
        if (ev.keycode == 125 || ev.keycode == 126)
            IPC::Socket2::sock()->postEvent({"memorakeyup", "super"});
        else if (ev.keycode == 56 || ev.keycode == 100)
            IPC::Socket2::sock()->postEvent({"memorakeyup", "alt"});
    });
    g_button = Event::bus()->m_events.input.mouse.button.listen([](const auto&, auto&) { chordWithSuper(); });
    memoraTitlebarInit(handle);
    memoraTouchInit(handle);
    return {"memora-minimize", "Minimize buttons send windows to the Memora Dock; title bars for apps without their own", "Memora", "1.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    memoraTitlebarExit();
    memoraTouchExit();
    g_state.clear();
    g_open.reset();
    g_close.reset();
    g_key.reset();
    g_button.reset();
}
