// memora-minimize: Hyprland ignores the minimize button of apps (a client's
// minimize request). This plugin turns that request into the IPC event
// "minimized>>ADDRESS,1", which the Memora shell answers by putting the window
// in the Dock.
// It also reports when Super or Alt is let go ("memorakeyup>>super" / "alt"):
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

static HANDLE                                         PHANDLE = nullptr;
static CHyprSignalListener                            g_open, g_close, g_key;
static std::unordered_map<void*, CHyprSignalListener> g_state;

static void watch(PHLWINDOW w) {
    PHLWINDOWREF ref = w;
    g_state[w.get()] = w->backend().m_events.stateRequest.listen([ref](const Desktop::View::SBackendStateRequest& req) {
        auto win = ref.lock();
        if (win && req.minimized.value_or(false))
            IPC::Socket2::sock()->postEvent({"minimized", std::format("{:x},1", (uintptr_t)win.get())});
    });
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;
    g_open  = Event::bus()->m_events.window.open.listen([](PHLWINDOW w) { watch(w); });
    g_close = Event::bus()->m_events.window.close.listen([](PHLWINDOW w) { g_state.erase(w.get()); });
    g_key   = Event::bus()->m_events.input.keyboard.key.listen([](const auto& ev, auto&) {
        if (ev.state != WL_KEYBOARD_KEY_STATE_RELEASED)
            return;
        // evdev codes: 125/126 Super, 56/100 Alt
        if (ev.keycode == 125 || ev.keycode == 126)
            IPC::Socket2::sock()->postEvent({"memorakeyup", "super"});
        else if (ev.keycode == 56 || ev.keycode == 100)
            IPC::Socket2::sock()->postEvent({"memorakeyup", "alt"});
    });
    return {"memora-minimize", "Minimize buttons send windows to the Memora Dock", "Memora", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_state.clear();
    g_open.reset();
    g_close.reset();
    g_key.reset();
}
