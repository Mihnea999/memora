import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Memora AI"
  property var cfg: ({ provider: "anthropic", model: "", baseUrl: "" })
  property bool hasKey: false
  property string test: ""
  readonly property string dir: Quickshell.env("HOME") + "/.config/memora"

  FileView {
    id: cfgFile
    path: p.dir + "/ai.json"
    printErrors: false
    onLoaded: { try { p.cfg = Object.assign({ provider: "anthropic", model: "", baseUrl: "" }, JSON.parse(text())) } catch (e) {} }
  }
  Kit.Cmd { id: keyCheck; onDone: out => p.hasKey = out.trim() === "yes" }
  readonly property string keyName: ({ anthropic: "ANTHROPIC_API_KEY", deepseek: "DEEPSEEK_API_KEY" })[p.cfg.provider] || "OPENAI_API_KEY"
  function checkKey() { keyCheck.exec(["bash", "-c", "grep -qE '^" + p.keyName + "=.+' \"$1\" 2>/dev/null && echo yes", "_", p.dir + "/ai.secret"]) }
  onKeyNameChanged: checkKey()
  Kit.Cmd { id: saver; onDone: p.checkKey() }
  // The answer, or what went wrong (errors come on stderr); never more than a minute.
  Kit.Cmd { id: tester; onDone: out => p.test = out.trim() ? out.trim().split("\n").slice(-4).join("\n") : "No answer. Check the key and the internet connection." }
  Component.onCompleted: saver.done("")

  function save(k, v) {
    const c = Object.assign({}, cfg); c[k] = v; cfg = c
    cfgFile.setText(JSON.stringify(c, null, 2) + "\n")
  }
  function saveKey(name, value) {
    saver.exec(["bash", "-c", "umask 077; mkdir -p \"$1\"; f=\"$1/ai.secret\"; touch \"$f\"; grep -v \"^$2=\" \"$f\" > \"$f.tmp\"; printf '%s=%s\\n' \"$2\" \"$3\" >> \"$f.tmp\"; mv \"$f.tmp\" \"$f\"", "_", dir, name, value])
  }

  Kit.Group {
    Kit.Row {
      label: "Runs on"; badge: "ai"; badgeColor: "#8a5cff"; last: true
      Kit.Choice {
        value: p.cfg.provider
        options: [{ text: "Claude", value: "anthropic" }, { text: "DeepSeek", value: "deepseek" }, { text: "Claude Code", value: "claude-code" }, { text: "Ollama", value: "ollama" }, { text: "Other", value: "openai" }]
        // Each service has its own models: switching starts from its default.
        onPicked: v => { if (v !== p.cfg.provider) { p.save("model", ""); p.save("provider", v) } }
      }
    }
  }

  Kit.Group {
    header: "Claude Code"
    visible: p.cfg.provider === "claude-code"
    footer: "Get Claude Code from the App Store (AI)."
    Kit.Row {
      label: "Account"; last: true
      Kit.Button { text: "Sign In…"; primary: true; onClicked: Quickshell.execDetached(["memora-float", "bash", "-lc", "claude /login; echo; read -rsn1 -p 'Done. Press a key to close.'"]) }
    }
  }

  Kit.Group {
    header: "Account"
    visible: p.cfg.provider === "anthropic" || p.cfg.provider === "deepseek" || p.cfg.provider === "openai"
    Kit.Row {
      label: "API key"; detail: p.hasKey ? "Saved on this computer" : "Not set"
      RowLayout { spacing: 8
        Kit.Field { id: keyField; secret: true; placeholder: p.cfg.provider === "anthropic" ? "sk-ant-…" : (p.cfg.provider === "deepseek" ? "sk-…" : "Key"); width: 220 }
        Kit.Button { text: "Save"; primary: true; onClicked: { p.saveKey(p.keyName, keyField.text); keyField.text = "" } }
      }
    }
    Kit.Row {
      visible: p.cfg.provider === "openai"
      label: "Server address"; last: true
      Kit.Field { text: p.cfg.baseUrl; placeholder: "https://…/v1"; width: 260; onAccepted: p.save("baseUrl", text) }
    }
    Kit.Row {
      visible: p.cfg.provider === "anthropic" || p.cfg.provider === "deepseek"
      label: "Get a key"; detail: p.cfg.provider === "deepseek" ? "platform.deepseek.com" : "console.anthropic.com"; last: true
      Kit.Button { text: "Open…"; onClicked: Quickshell.execDetached(["xdg-open", p.cfg.provider === "deepseek" ? "https://platform.deepseek.com/api_keys" : "https://console.anthropic.com/settings/keys"]) }
    }
  }

  // Claude (API or Claude Code): pick a model and how hard it thinks. Also from
  // the Memora AI window (click the model name at the top).
  readonly property bool claude: p.cfg.provider === "anthropic" || p.cfg.provider === "claude-code"
  Kit.Group {
    header: "Model"
    visible: p.claude
    Kit.Row {
      label: "Model"
      Kit.Choice {
        value: p.cfg.model || (p.cfg.provider === "claude-code" ? "" : "claude-opus-5-5")
        options: (p.cfg.provider === "claude-code" ? [{ text: "Default", value: "" }] : []).concat([
          { text: "Fable 5.1", value: "claude-fable-5-1" }, { text: "Opus 5.5", value: "claude-opus-5-5" },
          { text: "Sonnet 5.5", value: "claude-sonnet-5-5" }, { text: "Haiku 5.5", value: "claude-haiku-5-5" }])
        onPicked: v => p.save("model", v)
      }
    }
    Kit.Row {
      label: "Effort"; last: true
      Kit.Choice {
        value: p.cfg.effort || "high"
        options: [{ text: "Low", value: "low" }, { text: "Medium", value: "medium" }, { text: "High", value: "high" }, { text: "Extra high", value: "xhigh" }, { text: "Max", value: "max" }]
        onPicked: v => p.save("effort", v)
      }
    }
  }
  Kit.Group {
    header: "Model"
    visible: !p.claude
    Kit.Row {
      label: "Model"; detail: p.cfg.provider === "deepseek" ? "Default: deepseek-chat" : (p.cfg.provider === "ollama" ? "e.g. qwen3:8b" : "")
      last: true
      Kit.Field { text: p.cfg.model; placeholder: "default"; width: 220; onAccepted: p.save("model", text) }
    }
  }

  Kit.Group {
    footer: p.test
    Kit.Row {
      label: "Try it"; last: true
      RowLayout { spacing: 8
        Kit.Button { text: "Test"; onClicked: { p.test = "Asking…"; tester.exec(["bash", "-c", "timeout 60 memora-ai ask 'Reply with one short sentence: say hello from Memora.' </dev/null 2>&1 || [ $? != 124 ] || echo 'No answer within a minute. Check the internet connection.'"]) } }
        Kit.Button { text: "Open Memora AI"; primary: true; onClicked: Quickshell.execDetached(["memora-ai", "window"]) }
      }
    }
  }
}
