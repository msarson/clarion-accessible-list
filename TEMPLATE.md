# Global template — accessible browses across a whole app

`AccBrowse.tpl` is a **global (APPLICATION) extension** that makes **every ABC
browse** in an application screen-reader accessible, with no per-browse work.
It's the "tick one box, all 500 lists done" path for AppGen apps.

> Hand-coded windows don't need the template — use `AccListCls` directly (see
> [INTEGRATION.md](INTEGRATION.md)). The template is only for ABC/AppGen browses.

---

## Design — why it's done this way

Two non-obvious constraints shaped this:

1. **Don't derive `BrowseClass`.** It's tempting to subclass `BrowseClass`
   globally, but real apps already derive it (translation tools, resizers, grid
   add-ons). The ABC class chain allows only one base, so a second derivation
   collides. **The template injects *additive* embed code into each browse's
   already-generated methods instead** — compatible with everything.

2. **A queue-bound list exposes no cell data and no queue reference at runtime**
   (`PROPLIST:` is format-only; `PROP:From` is write-only). So the wiring has to
   happen where the queue *is* known: inside the browse object, whose `Init`
   receives the list FEQ and the queue as parameters.

The mechanism is the same one Clarion's own `abblob.tpw` uses to hook every
browse — `#AT(%BrowserMethodCodeSection), WHERE(%pClassMethod = '…')`:

| Browse method (embed) | Injected line | Effect |
|---|---|---|
| `Init(SIGNED ListBox, … QUEUE Q, …)` | `AccListAttach(ListBox, Q, ADDRESS(SELF))` | create the `IAccessible` object for this list+queue |
| `TakeNewSelection()` | `AccListNotify(ADDRESS(SELF))` | fire `EVENT_OBJECT_FOCUS` so the reader follows arrows |
| `Kill()` | `AccListDetach(ADDRESS(SELF))` | restore the subclass, release the object |

`ListBox` (the list FEQ) and `Q` (the queue) are **parameters of the browse's
`Init`**, so they're in scope exactly where we need them. `ADDRESS(SELF)` — the
browse object's address — is a stable per-browse key available in all three
methods, so the helpers always act on the right list. The helpers live in
`AccList.clw` (`AccListAttach` / `AccListNotify` / `AccListDetach`).

---

## Files involved

| File | Role |
|---|---|
| `AccList.inc` / `AccList.clw` | the runtime engine (`AccListCls` + the three helpers) |
| `AccListLink.inc` | prototypes for the helpers — added to the global map by the template |
| `AccBrowse.tpl` | the global extension itself |

---

## Installing it in an app

1. **Register the template:** Clarion IDE → *Setup → Template Registry →
   Register*, pick `AccBrowse.tpl`.

2. **Add the source + lib to the app project:**
   - `AccList.inc`, `AccList.clw`, `AccListLink.inc` on the source path
     (`AccList.clw` auto-links via `LINK()` in `AccList.inc`).
   - `oleacc.lib` in the project libraries.

3. **Add the project defines** (Project → Properties → Defines):
   ```
   _svLinkMode_=>1;_svDllMode_=>0
   ```

4. **Add the global extension:** Application → *Global Properties → Extensions →
   Insert* → **Accessible Lists - all browses (MSAA / screen readers)**. Leave
   *Enable accessible browses* ticked.

5. Generate, compile, run. Every browse is now accessible — verify with Inspect
   (MSAA mode) or Narrator (see [INTEGRATION.md](INTEGRATION.md#verifying-it-works)).

---

## Status / things to verify in your AppGen

This template is a **working draft built from the ABC template sources**
(`ABBROWSE.TPW`, `abblob.tpw`) — the structure and embed points are taken
straight from how Clarion's own templates hook browses. It has **not** been
round-tripped through a full AppGen generate+compile here, so confirm these in
your environment (all are easy to adjust in the `#AT … WHERE` clauses):

- **`Init` prototype string** — the `WHERE` matches
  `'(SIGNED ListBox,*STRING Posit,VIEW V,QUEUE Q,RelationManager RM,WindowManager WM)'`
  exactly (from `ABBROWSE.TPW`). If a future ABC tweaks the signature, update the
  `WHERE`.
- **`ADDRESS(SELF)`** as the per-browse key — if your build prefers, key on the
  queue instead (`ADDRESS(Q)` in `Init`, `ADDRESS(SELF.ListQueue)` elsewhere);
  the helpers only need a value that's identical across the three methods.
- **APPLICATION scope reaching every procedure's browse embeds** — if your AppGen
  version doesn't propagate the `%BrowserMethodCodeSection` injections from a
  *global* extension, add the extension at the *procedure* level on browse
  procedures instead (same three `#AT` blocks, identical behaviour).

If anything doesn't take, the per-browse manual wiring in
[INTEGRATION.md](INTEGRATION.md) is the guaranteed fallback and uses the same
`AccListCls`.

---

## Lifetime note

`AccListAttach` `NEW`s an `AccListCls`; `AccListDetach` (browse `Kill`) calls
`AccListCls.Kill()` then `Release()` — the object frees once COM has also let go,
so there's no premature-free crash and no leak across repeated window opens.
