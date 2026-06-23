# Clarion Accessible List

Make Clarion `LIST` controls readable by Windows screen readers (NVDA, JAWS,
Narrator) for **WCAG / Section 508** compliance — with a drop-in reusable class
and no per-control plumbing.

Clarion's `LIST`/`DROP` controls are owner-drawn custom windows (class
`ClaList…` / `ClaDrop…`). They expose **no native MSAA/UIA**, so a screen reader
that lands on one reads nothing — it shows up in Inspect as an unnamed
`pane`/`window`. This library fixes that by subclassing the control and
answering `WM_GETOBJECT` with a Clarion-implemented **`IAccessible`** object that
reports the list, its rows, the selection, and live focus changes.

> Built entirely in Clarion on top of the **svcom** COM-support classes that ship
> with Clarion — no C/C++ helper DLL required.

---

## What's in the repo

| File | Purpose |
|------|---------|
| `AccList.inc` | Declarations: the `IAccessible` interface + the `AccListCls` class. |
| `AccList.clw` | The engine — subclassing, the `IAccessible` implementation, and the **generic row renderer**. Write-once; you never edit this. |
| `AccDemo.clw` | Demo program: **two** lists with different schemas (text vs numeric/decimal) proving the generic renderer and multi-control routing. |
| `AccDemo.cwproj` / `AccDemo.sln` | Buildable project for the demo. |
| `oleacc.lib` | 32-bit import library for `oleacc.dll` (see below). |
| `INTEGRATION.md` | Step-by-step for adding it to your own app (hand-coded **and** ABC). |

---

## How it works

```
Screen reader ──WM_GETOBJECT──▶ subclassed LIST hwnd
                                      │
                                      ▼
                         LresultFromObject(IID_IAccessible, …)
                                      │
                                      ▼
                        AccListCls : IAccessible   (your object)
                          ├─ get_accChildCount  → RECORDS(queue)
                          ├─ get_accName(n)      → generic row text
                          ├─ get_accRole(n)      → list / list item
                          ├─ get_accState(n)     → selected / focused
                          └─ get_accFocus        → current row
```

1. **Subclass** the control's HWND (`SetWindowLong`/`GWL_WNDPROC`). A single
   shared window proc routes `WM_GETOBJECT` to the right object via an
   HWND→object registry, so any number of lists per window "just work".
2. **Answer `WM_GETOBJECT`** for `OBJID_CLIENT` with `LresultFromObject`, handing
   back our `IAccessible`.
3. **Render rows generically** — no hard-coded field names (see below).
4. **Fire `NotifyWinEvent(EVENT_OBJECT_FOCUS,…)`** on selection change so the
   reader follows the arrow keys.

### Generic row rendering (no schema knowledge)

A queue-bound `LIST` does **not** expose cell text through any property
(`PROPLIST:` is format/style only, and `PROP:From` is write-only). The data
lives in the queue. So the renderer reads it generically:

```clarion
GET(SELF.Q, RowNo)                              ! load the row
LOOP col = 1 TO 256
  IF ~SELF.Feq{PROPLIST:Exists, col} THEN BREAK.
  fld = SELF.Feq{PROPLIST:FieldNo, col}         ! which queue field feeds this column
  pic = SELF.Feq{PROPLIST:Picture, col}         ! the column's display picture
  cell = FORMAT(WHAT(SELF.Q, fld), pic)         ! WHAT() = field BY NUMBER, no names
  …
END
```

`WHAT(queue, n)` reads field *n* by position, so the wrapper renders **any**
list — you only pass it the control and its `FROM` queue.

---

## svcom — the COM support we build on

`svcom` is SoftVelocity's COM-support library, shipped with Clarion in
`…\Clarion11\LibSrc\win\svcom.inc` / `svcom.clw` (and `svcomdef.inc`). It is what
makes implementing a COM **server** interface possible in pure Clarion. We use:

| svcom item | Used for |
|------------|----------|
| `CCOMUserObject` | Base class that implements `IUnknown` (ref-counted `QueryInterface`/`AddRef`/`Release`). `AccListCls` derives from it. |
| `IUnknown` / `IDispatch` (declared `INTERFACE,COM`) | The vtable pattern our `IAccessible` extends (`INTERFACE(IDispatch),COM`). |
| `CBStr` | Builds real OLE `BSTR`s via `SysAllocString` — used for `get_accName`. |
| `tVariant`, `VT_I4`, `S_OK`, `E_NOTIMPL`, `DISP_E_*` | VARIANT struct + HRESULT/VARENUM equates. |

Pull it in with one line (it transitively includes `svcomdef.inc` and `svapi.inc`):

```clarion
INCLUDE('svcom.inc'),ONCE
```

> ⚠️ **svcom gotcha (important).** `CCOMUserObject.IUnknown.QueryInterface`
> (svcom.clw) is hard-wired to answer **only** `IUnknown` and does **not**
> dispatch back to your override. If you let it answer `QI(IUnknown)`, COM takes
> *its* pointer as the object's identity and then can't get `IAccessible` from it
> → `LresultFromObject` fails with `E_NOINTERFACE`. The fix (in `AccList.clw`):
> answer `IUnknown` yourself and return **one** consistent pointer
> (`ADDRESS(SELF.IAccessible)`) for `IUnknown`/`IDispatch`/`IAccessible`.

---

## Build setup & compiler directives

This is a **32-bit** technique (Clarion builds 32-bit EXEs; the accessibility
APIs are cross-bitness so 64-bit screen readers talk to it fine).

### 1. `oleacc.lib`

`AccList.clw` calls `LresultFromObject` from `oleacc.dll`. Clarion needs an
import library. A 32-bit `oleacc.lib` is committed here, made with **LibMaker**
from the 32-bit DLL:

```
C:\Windows\SysWOW64\oleacc.dll      ← 32-bit (use this)
C:\Windows\System32\oleacc.dll      ← 64-bit (do NOT use)
```

(On 64-bit Windows the names are backwards: `SysWOW64` holds the 32-bit copy.)
Add the lib to the project (already done in `AccDemo.cwproj`):

```xml
<Library Include="oleacc.lib" />
```

### 2. svcom link-mode constants

svcom needs these compiler defines or it won't link. They're set in
`AccDemo.cwproj` under `DefineConstants`:

```
_svLinkMode_ = 1        ! link svcom statically into the EXE
_svDllMode_  = 0        ! not consuming svcom from a DLL
```

In the project file that is (the `%3b` is an escaped `;`):

```xml
<DefineConstants>_svLinkMode_=&gt;1%3b_svDllMode_=&gt;0</DefineConstants>
```

### 3. API prototype attributes

Every Win32/oleacc/ole32 import in the `MAP` uses specific attributes — they
matter:

| Attribute | Meaning |
|-----------|---------|
| `PASCAL`  | `__stdcall` calling convention (required for Win32 APIs and COM). |
| `RAW`     | Pass the raw address of a string/group/pointer, **not** a Clarion string descriptor. Needed for `LPSTR`/`VARIANT*`/buffers. |
| `NAME('…A')` | The exact exported symbol, e.g. `SetWindowLongA`, `RtlMoveMemory`. |
| `PROC`    | Call may be used as a procedure (return value ignorable). |

```clarion
SetWindowLong(LONG hWnd, LONG nIndex, LONG dwNewLong),LONG,PROC,PASCAL,RAW,NAME('SetWindowLongA')
```

### 4. Line endings — **CRLF required**

Clarion's compiler rejects LF-only source. All `.clw`/`.inc` here are CRLF, and
`.gitattributes` forces `eol=crlf` on checkout so a clone on any machine stays
compilable regardless of `core.autocrlf`.

### Build the demo

1. Open `AccDemo.sln` in the Clarion IDE (or build `AccDemo.cwproj`).
2. Ensure `oleacc.lib` is in the project and the `DefineConstants` above are set.
3. Build (Win32) and run.

---

## The hard-won lessons (why the code looks the way it does)

These are the non-obvious things that took real debugging. If you adapt this,
keep them:

1. **`OleInitialize(0)` on the thread.** `IAccessible` marshalling needs an STA.
   Without it `LresultFromObject` cannot marshal the object.
2. **One identity pointer in `QueryInterface`** — see the svcom gotcha above.
3. **`[in] VARIANT` is passed BY VALUE (16 bytes).** Clarion passes a `GROUP` by
   *address*, so a `VARIANT` parameter declared as `*tVariant` mismatches the
   ABI, leaks 12 bytes of stack per call, and crashes. Declare each `[in] VARIANT`
   as **four `LONG`s** (`vcA, vcB, vcVal, vcD`); the child id (`lVal`) is the 3rd
   long, `vcVal`.
4. **`[out] VARIANT*` must NOT be `*tVariant` either.** A Clarion group-reference
   doesn't match the raw `VARIANT*` the COM stub passes → a bad-pointer write →
   `STATUS_FATAL_USER_CALLBACK_EXCEPTION` (`0xC000041D` / BEX). Receive it as a
   plain `LONG` and write a fully-cleared local `tVariant` with `CopyMemory`.
5. **`NotifyWinEvent(EVENT_OBJECT_FOCUS, hwnd, OBJID_CLIENT, row)`** on selection
   change — a Clarion list keeps the HWND focused while only the internal
   selection moves, so without this the reader won't follow arrow keys.

---

## Limitations / roadmap

- `accLocation` returns the whole-control rectangle; per-row rectangles (for the
  focus highlight and spatial navigation) are a refinement.
- Targets `LIST`; `DROP` (combo) controls are the obvious next addition.
- No sorting/locator announcements yet.
- Object lifetime is window-scoped and not `DISPOSE`d on close (sidesteps a COM
  ref-count trap); a production build can add a final `Release`.
- A **global extension template** to auto-apply `Init`/`NotifySelection`/`Kill`
  across hundreds of controls is the intended next step (in ABC the queue comes
  straight from the `BrowseClass`).

---

## Testing

- **Inspect.exe** (Windows SDK): switch to **MSAA** mode, hover the list — you
  should see `Role: list`, a child count, and per-row names.
- **AccEvent.exe**: watch `EVENT_OBJECT_FOCUS` fire as you arrow.
- **Narrator** (`Win`+`Ctrl`+`Enter`): tab into the list and arrow — rows are
  spoken.

---

## License

MIT — see [LICENSE](LICENSE).
