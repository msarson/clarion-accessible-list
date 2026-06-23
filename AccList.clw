          MEMBER()
! ============================================================================
!  AccList.clw  -  implementation of the reusable AccListCls (see AccList.inc)
! ============================================================================
  INCLUDE('AccList.inc'),ONCE

          MAP
            MODULE('Win32API')
              SetWindowLong(LONG hWnd, LONG nIndex, LONG dwNewLong),LONG,PROC,PASCAL,RAW,NAME('SetWindowLongA')
              CallWindowProc(LONG lpPrev, LONG hWnd, LONG Msg, LONG wParam, LONG lParam),LONG,PASCAL,RAW,NAME('CallWindowProcA')
              GetWindowRect(LONG hWnd, LONG lpRect),LONG,PASCAL,RAW,NAME('GetWindowRect')
              NotifyWinEvent(LONG winEvent, LONG hWnd, LONG idObject, LONG idChild),PASCAL,RAW,NAME('NotifyWinEvent')
              CopyMemory(LONG Dest, LONG Source, LONG Length),PASCAL,RAW,NAME('RtlMoveMemory')
              OleInitialize(LONG pvReserved),LONG,PASCAL,RAW,NAME('OleInitialize')
              OleUninitialize(),PASCAL,NAME('OleUninitialize')
              LresultFromObject(LONG riid, LONG wParam, LONG pUnk),LONG,PASCAL,RAW,NAME('LresultFromObject')
            END
            AccList_WndProc(LONG hWnd, LONG uMsg, LONG wParam, LONG lParam),LONG,PASCAL
          END

!GWL_WNDPROC             EQUATE(-4)        ! already defined by svapi.inc (via svcom.inc)
WM_GETOBJECT  EQUATE(003Dh)
OBJID_CLIENT  EQUATE(0FFFFFFFCh)
EVENT_OBJECT_FOCUS    EQUATE(08005h)
ROLE_SYSTEM_LIST  EQUATE(033h)
ROLE_SYSTEM_LISTITEM  EQUATE(022h)
STATE_SYSTEM_FOCUSED  EQUATE(00000004h)
STATE_SYSTEM_SELECTED EQUATE(00000002h)
STATE_SYSTEM_FOCUSABLE    EQUATE(00100000h)
STATE_SYSTEM_SELECTABLE   EQUATE(00200000h)

RECT      GROUP,TYPE
left        LONG
top         LONG
right       LONG
bottom      LONG
          END

! IID_IAccessible {618736E0-3C3D-11CF-810C-00AA00389B71}
_IAccessible  GROUP
Data1           LONG(0618736E0h)
Data2           SHORT(03C3Dh)
Data3           SHORT(011CFh)
Data4           STRING('<081h><00Ch><0><0AAh><0><038h><09Bh><071h>')
              END

! Registry: maps a subclassed control HWND -> its AccListCls instance, so the
! single shared subclass proc can route WM_GETOBJECT to the right object.
AccRegQ   QUEUE,STATIC
RegHWnd     LONG
RegObj      &AccListCls
          END

! ============================================================================
!  Public methods
! ============================================================================
AccListCls.Init   PROCEDURE(LONG pFeq, *QUEUE pQ)
  CODE
  SELF.Feq    = pFeq
  SELF.Q     &= pQ
  SELF.hWnd   = pFeq{PROP:Handle}
  OleInitialize(0)                                  ! IAccessible marshalling needs an STA (ref-counted)
  AccRegQ.RegHWnd = SELF.hWnd                        ! register before we subclass
  AccRegQ.RegObj &= SELF
  ADD(AccRegQ)
  SELF.OldProc = SetWindowLong(SELF.hWnd, GWL_WNDPROC, ADDRESS(AccList_WndProc))

AccListCls.Kill   PROCEDURE
i                   LONG
  CODE
  IF SELF.hWnd AND SELF.OldProc
    SetWindowLong(SELF.hWnd, GWL_WNDPROC, SELF.OldProc)   ! restore BEFORE the control dies
  END
  LOOP i = RECORDS(AccRegQ) TO 1 BY -1
    GET(AccRegQ, i)
    IF AccRegQ.RegHWnd = SELF.hWnd
      DELETE(AccRegQ)
    END
  END
  OleUninitialize()
  SELF.hWnd   = 0
  SELF.OldProc = 0

AccListCls.NotifySelection    PROCEDURE
  CODE
  IF SELF.hWnd
    NotifyWinEvent(EVENT_OBJECT_FOCUS, SELF.hWnd, OBJID_CLIENT, SELF.CurRow())
  END

! ============================================================================
!  Protected helpers
! ============================================================================
AccListCls.RowCount   PROCEDURE
  CODE
  IF SELF.Q &= NULL THEN RETURN 0.
  RETURN RECORDS(SELF.Q)

AccListCls.CurRow PROCEDURE
  CODE
  IF ~SELF.Feq THEN RETURN 0.
  RETURN SELF.Feq{PROP:Selected}

AccListCls.RowText    PROCEDURE(LONG pRow)
RowTxt                  CSTRING(1024)
cellTxt                 CSTRING(256)
pic                     CSTRING(64)
col                     LONG
fld                     LONG
  CODE
  IF SELF.Q &= NULL THEN RETURN ''.
  IF pRow < 1 OR pRow > SELF.RowCount() THEN RETURN ''.
  GET(SELF.Q, pRow)
  IF ERRORCODE() THEN RETURN ''.
  LOOP col = 1 TO 256                                ! walk the visible columns
    IF ~SELF.Feq{PROPLIST:Exists, col} THEN BREAK.
    fld = SELF.Feq{PROPLIST:FieldNo, col}            ! which queue field feeds this column
    IF ~fld THEN CYCLE.                              ! skip non-data columns (icons etc.)
    pic = SELF.Feq{PROPLIST:Picture, col}            ! the column's display picture
    IF pic
      cellTxt = FORMAT(WHAT(SELF.Q, fld), pic)       ! WHAT() = field by NUMBER (no field names)
    ELSE
      cellTxt = WHAT(SELF.Q, fld)
    END
    cellTxt = CLIP(LEFT(cellTxt))
    IF cellTxt
      IF RowTxt THEN RowTxt = CLIP(RowTxt) & ', '.
      RowTxt = CLIP(RowTxt) & cellTxt
    END
  END
  RETURN CLIP(RowTxt)

! ============================================================================
!  QueryInterface - one identity pointer for IUnknown/IDispatch/IAccessible
! ============================================================================
AccListCls.QueryInterface PROCEDURE(LONG riid, *LONG ppvObject)
  CODE
  IF SELF.IsEqualIID(riid, ADDRESS(_IAccessible)) OR |
    SELF.IsEqualIID(riid, ADDRESS(_IDispatch)) OR |
    SELF.IsEqualIID(riid, ADDRESS(_IUnknown))
    ppvObject = ADDRESS(SELF.IAccessible)
    SELF.AddRef()
    RETURN S_OK
  END
  ppvObject = 0
  RETURN E_NOINTERFACE

AccListCls.IAccessible.QueryInterface PROCEDURE(LONG riid, *LONG ppvObject)
  CODE
  RETURN SELF.QueryInterface(riid, ppvObject)

AccListCls.IAccessible.AddRef PROCEDURE
  CODE
  RETURN SELF.AddRef()

AccListCls.IAccessible.Release    PROCEDURE
  CODE
  RETURN SELF.Release()

! --- IDispatch (screen readers call the vtable directly; stubs are fine) ----
AccListCls.IAccessible.GetTypeInfoCount   PROCEDURE(*LONG pctinfo)
  CODE
  pctinfo = 0
  RETURN S_OK

AccListCls.IAccessible.GetTypeInfo    PROCEDURE(LONG iTInfo, LONG lcid, LONG ppTInfo)
  CODE
  RETURN E_NOTIMPL

AccListCls.IAccessible.GetIDsOfNames  PROCEDURE(LONG riid, LONG prgszNames, LONG cNames, LONG lcid, LONG prgDispId)
  CODE
  RETURN DISP_E_UNKNOWNNAME

AccListCls.IAccessible.Invoke PROCEDURE(LONG dispIdMember, LONG riid, LONG lcid, SHORT wFlags, LONG pDispParams, LONG pVarResult, LONG pExcepInfo, LONG puArgErr)
  CODE
  RETURN DISP_E_MEMBERNOTFOUND

! --- IAccessible ------------------------------------------------------------
AccListCls.IAccessible.get_accParent  PROCEDURE(*LONG ppdispParent)
  CODE
  ppdispParent = 0
  RETURN S_FALSE

AccListCls.IAccessible.get_accChildCount  PROCEDURE(*LONG pcountChildren)
  CODE
  pcountChildren = SELF.RowCount()
  RETURN S_OK

AccListCls.IAccessible.get_accChild   PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG ppdispChild)
  CODE
  ppdispChild = 0                                    ! rows are simple-element children
  RETURN S_FALSE

AccListCls.IAccessible.get_accName    PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG pszName)
RowTxt                                  CSTRING(1024)
bs                                      CBStr
  CODE
  pszName = 0
  IF vcVal = 0
    IF ~SELF.NameTxt THEN RETURN S_FALSE.            ! no explicit name -> let the SR use the control's own
    RowTxt = SELF.NameTxt
  ELSE
    RowTxt = SELF.RowText(vcVal)
    IF ~RowTxt THEN RETURN S_FALSE.
  END
  bs.Init(RowTxt, false)                             ! false => caller owns/frees the BSTR
  pszName = bs.GetBStr()
  RETURN S_OK

AccListCls.IAccessible.get_accValue   PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG pszValue)
  CODE
  pszValue = 0
  RETURN S_FALSE

AccListCls.IAccessible.get_accDescription PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG pszDescription)
  CODE
  pszDescription = 0
  RETURN S_FALSE

AccListCls.IAccessible.get_accRole    PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, LONG pvarRole)
v                                       LIKE(tVariant)
  CODE
  CLEAR(v)
  v.vt = VT_I4
  IF vcVal = 0
    v.iVal = ROLE_SYSTEM_LIST
  ELSE
    v.iVal = ROLE_SYSTEM_LISTITEM
  END
  CopyMemory(pvarRole, ADDRESS(v), SIZE(tVariant))
  RETURN S_OK

AccListCls.IAccessible.get_accState   PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, LONG pvarState)
v                                       LIKE(tVariant)
  CODE
  CLEAR(v)
  v.vt = VT_I4
  IF vcVal = 0
    v.iVal = STATE_SYSTEM_FOCUSABLE
  ELSE
    v.iVal = STATE_SYSTEM_SELECTABLE + STATE_SYSTEM_FOCUSABLE
    IF vcVal = SELF.CurRow()
      v.iVal += STATE_SYSTEM_SELECTED + STATE_SYSTEM_FOCUSED
    END
  END
  CopyMemory(pvarState, ADDRESS(v), SIZE(tVariant))
  RETURN S_OK

AccListCls.IAccessible.get_accHelp    PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG pszHelp)
  CODE
  pszHelp = 0
  RETURN S_FALSE

AccListCls.IAccessible.get_accHelpTopic   PROCEDURE(*LONG pszHelpFile, LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG pidTopic)
  CODE
  pszHelpFile = 0
  pidTopic = 0
  RETURN S_FALSE

AccListCls.IAccessible.get_accKeyboardShortcut    PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG pszKeyboardShortcut)
  CODE
  pszKeyboardShortcut = 0
  RETURN S_FALSE

AccListCls.IAccessible.get_accFocus   PROCEDURE(LONG pvarChild)
v                                       LIKE(tVariant)
  CODE
  CLEAR(v)
  v.vt = VT_I4
  v.iVal = SELF.CurRow()                             ! the focused row
  CopyMemory(pvarChild, ADDRESS(v), SIZE(tVariant))
  RETURN S_OK

AccListCls.IAccessible.get_accSelection   PROCEDURE(LONG pvarChildren)
v                                           LIKE(tVariant)
  CODE
  CLEAR(v)
  v.vt = VT_I4
  v.iVal = SELF.CurRow()
  CopyMemory(pvarChildren, ADDRESS(v), SIZE(tVariant))
  RETURN S_OK

AccListCls.IAccessible.get_accDefaultAction   PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG pszDefaultAction)
  CODE
  pszDefaultAction = 0
  RETURN S_FALSE

AccListCls.IAccessible.accSelect  PROCEDURE(LONG flagsSelect, LONG vcA, LONG vcB, LONG vcVal, LONG vcD)
  CODE
  RETURN E_NOTIMPL

AccListCls.IAccessible.accLocation    PROCEDURE(*LONG pxLeft, *LONG pyTop, *LONG pcxWidth, *LONG pcyHeight, LONG vcA, LONG vcB, LONG vcVal, LONG vcD)
rc                                      LIKE(RECT)
  CODE
  IF GetWindowRect(SELF.hWnd, ADDRESS(rc))           ! whole-control rect (per-row is a refinement)
    pxLeft    = rc.left
    pyTop     = rc.top
    pcxWidth  = rc.right - rc.left
    pcyHeight = rc.bottom - rc.top
    RETURN S_OK
  END
  RETURN S_FALSE

AccListCls.IAccessible.accNavigate    PROCEDURE(LONG navDir, LONG vsA, LONG vsB, LONG vsVal, LONG vsD, LONG pvarEndUpAt)
v                                       LIKE(tVariant)
cnt                                     LONG
nxt                                     LONG
  CODE
  cnt = SELF.RowCount()
  nxt = 0
  CASE navDir
  OF 7                                               ! NAVDIR_FIRSTCHILD
    nxt = CHOOSE(cnt > 0, 1, 0)
  OF 8                                               ! NAVDIR_LASTCHILD
    nxt = cnt
  OF 5                                               ! NAVDIR_NEXT
  OROF 2                                             ! NAVDIR_DOWN
    IF vsVal < cnt THEN nxt = vsVal + 1.
  OF 6                                               ! NAVDIR_PREVIOUS
  OROF 1                                             ! NAVDIR_UP
    IF vsVal > 1 THEN nxt = vsVal - 1.
  END
  CLEAR(v)
  IF nxt > 0
    v.vt = VT_I4
    v.iVal = nxt
    CopyMemory(pvarEndUpAt, ADDRESS(v), SIZE(tVariant))
    RETURN S_OK
  END
  v.vt = VT_EMPTY
  CopyMemory(pvarEndUpAt, ADDRESS(v), SIZE(tVariant))
  RETURN S_FALSE

AccListCls.IAccessible.accHitTest PROCEDURE(LONG xLeft, LONG yTop, LONG pvarChild)
v                                   LIKE(tVariant)
rc                                  LIKE(RECT)
  CODE
  CLEAR(v)
  IF GetWindowRect(SELF.hWnd, ADDRESS(rc)) AND xLeft >= rc.left AND xLeft < rc.right |
    AND yTop >= rc.top AND yTop < rc.bottom
    v.vt = VT_I4
    v.iVal = 0                                       ! CHILDID_SELF
    CopyMemory(pvarChild, ADDRESS(v), SIZE(tVariant))
    RETURN S_OK
  END
  v.vt = VT_EMPTY
  CopyMemory(pvarChild, ADDRESS(v), SIZE(tVariant))
  RETURN S_FALSE

AccListCls.IAccessible.accDoDefaultAction PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD)
  CODE
  RETURN E_NOTIMPL

AccListCls.IAccessible.put_accName    PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, LONG szName)
  CODE
  RETURN E_NOTIMPL

AccListCls.IAccessible.put_accValue   PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, LONG szValue)
  CODE
  RETURN E_NOTIMPL

! ============================================================================
!  Shared subclass proc - routes WM_GETOBJECT to the right object by HWND
! ============================================================================
AccList_WndProc   PROCEDURE(LONG hWnd, LONG uMsg, LONG wParam, LONG lParam)
i                   LONG
obj                 &AccListCls
old                 LONG
lres                LONG
  CODE
  obj &= NULL
  old = 0
  LOOP i = 1 TO RECORDS(AccRegQ)
    GET(AccRegQ, i)
    IF AccRegQ.RegHWnd = hWnd
      obj &= AccRegQ.RegObj
      old = obj.OldProc
      BREAK
    END
  END
  IF obj &= NULL THEN RETURN 0.                       ! not ours (shouldn't happen)
  IF uMsg = WM_GETOBJECT AND lParam = OBJID_CLIENT
    lres = LresultFromObject(ADDRESS(_IAccessible), wParam, ADDRESS(obj.IAccessible))
    IF lres > 0 THEN RETURN lres.
  END
  RETURN CallWindowProc(old, hWnd, uMsg, wParam, lParam)
