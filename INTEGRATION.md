# Adding Accessible Lists to your application

This guide covers wiring `AccListCls` into an existing Clarion app — both
**hand-coded** windows and **ABC / AppGen** apps. For background on *how* it
works, see [README.md](README.md).

---

## Prerequisites (once per project)

1. **Add the two library files** to your app/project:
   - `AccList.inc`
   - `AccList.clw`

   `AccList.inc` declares the class with `MODULE('AccList.clw'),LINK('AccList.clw')`,
   so the engine is compiled and linked automatically — you only need
   `AccList.clw` reachable on the project's source path (you don't have to add it
   to the Compile list, though doing so is harmless).

2. **Add `oleacc.lib`** to the project libraries (copy the committed 32-bit lib,
   or regenerate it with LibMaker from `C:\Windows\SysWOW64\oleacc.dll`).

3. **Set the svcom link-mode constants** in the project's `DefineConstants`:
   ```
   _svLinkMode_=>1;_svDllMode_=>0
   ```
   (In the Clarion IDE: Project → Properties → Defines.)

4. Make sure your source stays **CRLF** (it already is if you didn't reformat it
   with a non-Clarion editor).

That's the whole project-level cost — once, regardless of how many lists.

---

## Per list: four touch points

For every `LIST` you want accessible:

```clarion
MyAcc   &AccListCls          ! 0. one reference per list (module/local data)
```

```clarion
! 1. After the window is OPEN and the list exists:
MyAcc &= NEW AccListCls
MyAcc.Init(?Browse, MyQueue) ! the control FEQ + its FROM queue
MyAcc.NameTxt = 'Customers'  ! optional spoken name for the list itself
```

```clarion
! 2. So the reader follows arrow keys / selection changes:
OF EVENT:NewSelection
  IF FIELD() = ?Browse THEN MyAcc.NotifySelection().
```

```clarion
! 3. Before the window closes (restores the subclass, deregisters):
MyAcc.Kill()
```

Multiple lists? Repeat with one `AccListCls` per control — the shared subclass
proc routes each control's `WM_GETOBJECT` to the right object automatically.

---

## Hand-coded window — full pattern

```clarion
CustQ    QUEUE
Name       STRING(40)
Balance    DECIMAL(11,2)
         END

Acc      &AccListCls

Win      WINDOW('Customers'),AT(,,200,160),SYSTEM,GRAY
           LIST,AT(4,4,192,140),USE(?Browse),FROM(CustQ), |
             FORMAT('120L(2)|M~Name~@s40@60R(2)|M~Balance~@n-11.2@')
         END

  CODE
  ! …fill CustQ…
  OPEN(Win)
  Acc &= NEW AccListCls
  Acc.Init(?Browse, CustQ)
  Acc.NameTxt = 'Customers'
  ACCEPT
    CASE EVENT()
    OF EVENT:NewSelection
      IF FIELD() = ?Browse THEN Acc.NotifySelection().
    END
  END
  Acc.Kill()
  CLOSE(Win)
```

---

## ABC / AppGen apps — where to embed

In a generated Browse procedure, use these embed points. The big win in ABC:
**the `BrowseClass` already holds the queue**, so you don't write any data code.

| Step | Embed point | Code |
|------|-------------|------|
| Declare | *Data* (Local Objects / Module data) | `Acc   &AccListCls` |
| Init | `WindowManager.Init`, **PRIORITY after the window opens** (e.g. after `OPEN(window)` / in `ThisWindow.Init` after `PARENT.Init` returns and the browse is set up) | `Acc &= NEW AccListCls` ; `Acc.Init(?Browse:1, Queue:Browse:1)` ; `Acc.NameTxt = 'Customers'` |
| Focus | `BrowseClass.TakeNewSelection` (or `ThisWindow.TakeEvent` on `EVENT:NewSelection` for `?Browse:1`) | `Acc.NotifySelection()` |
| Kill | `WindowManager.Kill`, **PRIORITY before** the window closes | `Acc.Kill()` |

Notes:
- `?Browse:1` is the generated list control; `Queue:Browse:1` is its `FROM`
  queue — both are standard AppGen names. Match them to your procedure.
- If you prefer, pass the BrowseClass's own queue reference; it is the same queue
  the list is bound to.
- Put `Init` late enough that `?Browse:1{PROP:Handle}` is valid (the window and
  control must exist).

---

## Choosing the spoken name

`NameTxt` is the accessible name of the **list as a whole** (what the reader says
when focus first lands on it). Leave it blank to let the screen reader fall back
to the control's own name/label. Row text is always generated automatically from
the columns.

---

## Verifying it works

1. **Inspect.exe** (Windows SDK, `…\bin\<ver>\x64\inspect.exe`): set the mode
   dropdown to **Microsoft Active Accessibility (MSAA)** and hover the list.
   Expect `Role: list`, a child count equal to your row count, and each row named
   from its columns.
2. **Narrator** (`Win`+`Ctrl`+`Enter`): tab into the list, arrow up/down — each
   row should be spoken. Use Narrator's **Speech Viewer** to read it silently.
3. **AccEvent.exe**: confirm `EVENT_OBJECT_FOCUS` fires on each arrow.

If Inspect's UIA view still shows a blank `pane`, that's expected — switch it to
**MSAA** mode (this object is MSAA; UIA only sometimes re-projects it).

---

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| Link error on `LresultFromObject` | `oleacc.lib` not in the project, or it's the 64-bit lib. Regenerate from `SysWOW64\oleacc.dll`. |
| Link errors mentioning `_svLinkMode_` / svcom | `DefineConstants` missing `_svLinkMode_=>1;_svDllMode_=>0`. |
| Compiler errors on otherwise-correct source | File got saved as LF. Re-save as CRLF (or rely on `.gitattributes`). |
| `LresultFromObject` returns a negative number (e.g. `-2147467262`) | `E_NOINTERFACE` — the `QueryInterface` identity fix isn't in place. Use `AccList.clw` as-is. |
| Reader reads the window but never the rows | Missing `NotifySelection()` on selection change, or `Init` ran before the control existed. |
| Crash (`0xC000041D` / BEX) when a reader queries it | An out-VARIANT was written through a Clarion group reference. Use `AccList.clw` as-is (it writes via `CopyMemory`). |
