// A Herdr app pane that shows an OpenSpec change folder as one markdown page.
// Open it with: pane.split {direction, mod: "spec-viewer", props: {folder}}.
import { View } from "gpui-kit";
import { v_flex, TextView } from "gpui-base";
import { exec, props, theme, watchFolder } from "herdr";

// The reading order of the story: why (proposal), how (design), what exactly (specs), the steps (tasks).
const JOIN = 'for f in proposal.md design.md specs/*/spec.md tasks.md; do [ -f "$f" ] && cat "$f" && echo; done; true';

export default class SpecViewer extends View {
  init(_props, cx) {
    this.text = "Loading the spec…";
    cx.spawn(async (cx) => {
      const folder = props().folder;
      for (;;) {
        const r = await exec("sh", ["-c", JOIN], { cwd: folder }).catch((e) => ({ stdout: `Cannot read ${folder}: ${e}` }));
        this.text = r.stdout || `No spec files in ${folder}`;
        cx.notify();
        await watchFolder(folder); // Reload when the spec changes.
      }
    });
  }

  render() {
    const t = theme();
    return v_flex().size_full().p(16).bg(t.background).text_color(t.foreground)
      .child(TextView.markdown("spec", this.text).scrollable().selectable());
  }
}
