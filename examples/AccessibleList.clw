          PROGRAM
!*****************************************************************************
!  AccessibleList.clw  -  expose a Clarion LIST to screen readers (MSAA)
!
!  Subclass the LIST's HWND, answer WM_GETOBJECT with a Clarion-implemented
!  IAccessible built on svcom's CCOMUserObject.
!
!  KEY LESSONS:
!   1. OleInitialize(0) - IAccessible marshalling needs an STA.
!   2. Answer QI(IUnknown) yourself, returning ONE pointer (self.IAccessible)
!      for IUnknown/IDispatch/IAccessible (svcom CCOMUserObject.IUnknown.
!      QueryInterface only knows IUnknown and breaks COM identity otherwise).
!   3. [in] VARIANT params are BY VALUE (16 bytes). Clarion passes a GROUP by
!      address, so declare each as FOUR LONGs (vcA,vcB,vcVal,vcD); child id
!      (lVal) = 3rd long = vcVal.
!   4. [out] VARIANT* params: do NOT use *tVariant (Clarion group-reference
!      doesn't match the raw VARIANT* the COM stub passes -> bad-pointer write
!      -> STATUS_FATAL_USER_CALLBACK_EXCEPTION / BEX). Receive the pointer as a
!      plain LONG and write a fully-initialised local tVariant with CopyMemory.
!   5. Shared state (NameQ, glo:CurChoice) guarded by an ICriticalSection.
!
!  Build: add oleacc.lib to the project. Trace via DebugView (OutputDebugString).
!*****************************************************************************

  include('svcom.inc'),once
!  include('cwsynchm.inc'),once          ! NewCriticalSection / ICriticalSection

          map
            module('user32')
              SetWindowLong(long hWnd, long nIndex, long dwNewLong),long,PROC,pascal,raw,name('SetWindowLongA')
              CallWindowProc(long lpPrevWndFunc, long hWnd, long Msg, long wParam, long lParam),long,pascal,raw,name('CallWindowProcA')
              GetWindowRect(long hWnd, long lpRect),long,pascal,raw,name('GetWindowRect')
              NotifyWinEvent(long winEvent, long hWnd, long idObject, long idChild),pascal,raw,name('NotifyWinEvent')
            end
            module('oleacc')                 ! add oleacc.lib to the project
              LresultFromObject(long riid, long wParam, long pUnk),long,pascal,raw,name('LresultFromObject')
            end
            module('kernel32')
              OutputDebugString(*cstring lpOutputString),pascal,raw,name('OutputDebugStringA')
              GetCurrentThreadId(),long,pascal,name('GetCurrentThreadId')
              CopyMemory(long Destination, long Source, long Length),pascal,raw,name('RtlMoveMemory')
            end
            module('ole32')
              OleInitialize(long pvReserved),long,pascal,raw,name('OleInitialize')
              OleUninitialize(),pascal,name('OleUninitialize')
            end
            ListWndProc(long hWnd, long uMsg, long wParam, long lParam),long,pascal
            DbgOut(string pMsg)
          end

!GWL_WNDPROC             equate(-4)        ! already defined by svapi.inc (via svcom.inc)
WM_GETOBJECT  equate(003Dh)
OBJID_CLIENT  equate(0FFFFFFFCh)
EVENT_OBJECT_FOCUS  equate(08005h)

ROLE_SYSTEM_LIST  equate(033h)
ROLE_SYSTEM_LISTITEM  equate(022h)
STATE_SYSTEM_FOCUSED  equate(00000004h)
STATE_SYSTEM_SELECTED equate(00000002h)
STATE_SYSTEM_FOCUSABLE    equate(00100000h)
STATE_SYSTEM_SELECTABLE   equate(00200000h)

RECT      group,type
left        long
top         long
right       long
bottom      long
          end

! IID_IAccessible {618736E0-3C3D-11CF-810C-00AA00389B71}
_IAccessible  group
Data1           long(0618736E0h)
Data2           short(03C3Dh)
Data3           short(011CFh)
Data4           string('<081h><00Ch><0><0AAh><0><038h><09Bh><071h>')
              end

! [in] VARIANT = 4 longs (vcVal = child id).  [out] VARIANT* = a plain long
! pointer (written via CopyMemory).
IAccessible   interface(IDispatch),com
get_accParent   procedure(*long ppdispParent),HRESULT
get_accChildCount   procedure(*long pcountChildren),HRESULT
get_accChild    procedure(long vcA, long vcB, long vcVal, long vcD, *long ppdispChild),HRESULT
get_accName     procedure(long vcA, long vcB, long vcVal, long vcD, *long pszName),HRESULT
get_accValue    procedure(long vcA, long vcB, long vcVal, long vcD, *long pszValue),HRESULT
get_accDescription  procedure(long vcA, long vcB, long vcVal, long vcD, *long pszDescription),HRESULT
get_accRole     procedure(long vcA, long vcB, long vcVal, long vcD, long pvarRole),HRESULT
get_accState    procedure(long vcA, long vcB, long vcVal, long vcD, long pvarState),HRESULT
get_accHelp     procedure(long vcA, long vcB, long vcVal, long vcD, *long pszHelp),HRESULT
get_accHelpTopic    procedure(*long pszHelpFile, long vcA, long vcB, long vcVal, long vcD, *long pidTopic),HRESULT
get_accKeyboardShortcut procedure(long vcA, long vcB, long vcVal, long vcD, *long pszKeyboardShortcut),HRESULT
get_accFocus    procedure(long pvarChild),HRESULT
get_accSelection    procedure(long pvarChildren),HRESULT
get_accDefaultAction    procedure(long vcA, long vcB, long vcVal, long vcD, *long pszDefaultAction),HRESULT
accSelect       procedure(long flagsSelect, long vcA, long vcB, long vcVal, long vcD),HRESULT
accLocation     procedure(*long pxLeft, *long pyTop, *long pcxWidth, *long pcyHeight, long vcA, long vcB, long vcVal, long vcD),HRESULT
accNavigate     procedure(long navDir, long vsA, long vsB, long vsVal, long vsD, long pvarEndUpAt),HRESULT
accHitTest      procedure(long xLeft, long yTop, long pvarChild),HRESULT
accDoDefaultAction  procedure(long vcA, long vcB, long vcVal, long vcD),HRESULT
put_accName     procedure(long vcA, long vcB, long vcVal, long vcD, long szName),HRESULT
put_accValue    procedure(long vcA, long vcB, long vcVal, long vcD, long szValue),HRESULT
              end

AccList   class(CCOMUserObject),implements(IAccessible),type
QueryInterface  procedure(long riid, *long ppvObject),HRESULT,derived
          end

NameQ     queue
NName       string(40)
NCity       string(30)
          end

glo:OldProc   long
glo:ListHWND  long
glo:CurChoice long(1)
glo:OleHr     long
!glo:Crit  &ICriticalSection
AccObj    &AccList

AppWindow     WINDOW('Accessible List Demo'),AT(,,260,170),GRAY,SYSTEM,FONT('Segoe UI',9)
                LIST,AT(8,8,244,128),USE(?Browse),FROM(NameQ),VSCROLL, |
                  FORMAT('90L(2)|M~Name~@s40@90L(2)|M~City~@s30@')
                BUTTON('Close'),AT(108,146,44,14),USE(?CloseBtn),STD(STD:Close)
              END

!=============================================================================
  code
  !glo:Crit &= NewCriticalSection()
  AccObj &= new AccList
  glo:OleHr = OleInitialize(0)
  DbgOut('OleInitialize hr=' & glo:OleHr & ' MAIN thread=' & GetCurrentThreadId())

  !glo:Crit.Wait()
  NameQ.NName = 'Alice Brown'  ; NameQ.NCity = 'London'   ; add(NameQ)
  NameQ.NName = 'Carlos Diaz'  ; NameQ.NCity = 'Madrid'   ; add(NameQ)
  NameQ.NName = 'Emma Foster'  ; NameQ.NCity = 'New York' ; add(NameQ)
  NameQ.NName = 'Hiro Tanaka'  ; NameQ.NCity = 'Tokyo'    ; add(NameQ)
  !glo:Crit.Release()

  open(AppWindow)
  glo:ListHWND = ?Browse{PROP:Handle}
  glo:OldProc  = SetWindowLong(glo:ListHWND, GWL_WNDPROC, address(ListWndProc))
  DbgOut('Subclass install: HWND=' & glo:ListHWND & ' OldProc=' & glo:OldProc)

  accept
    case event()
    of EVENT:NewSelection
      if field() = ?Browse
        !glo:Crit.Wait()
        glo:CurChoice = choice(?Browse)
        !glo:Crit.Release()
        NotifyWinEvent(EVENT_OBJECT_FOCUS, glo:ListHWND, OBJID_CLIENT, glo:CurChoice)
      end
    end
  end

  if glo:OldProc
    SetWindowLong(glo:ListHWND, GWL_WNDPROC, glo:OldProc)
  end
  close(AppWindow)
  dispose(AccObj)
  if glo:OleHr >= 0
    OleUninitialize()
  end
  !glo:Crit.Kill()
  return

!=============================================================================
ListWndProc   procedure(long hWnd, long uMsg, long wParam, long lParam)
lres            long
  code
  if uMsg = WM_GETOBJECT and lParam = OBJID_CLIENT and not AccObj &= null
    lres = LresultFromObject(address(_IAccessible), wParam, address(AccObj.IAccessible))
    DbgOut('WM_GETOBJECT thread=' & GetCurrentThreadId() & ' Lres=' & lres)
    if lres > 0
      return lres
    end
  end
  return CallWindowProc(glo:OldProc, hWnd, uMsg, wParam, lParam)

!=============================================================================
AccList.QueryInterface    procedure(long riid, *long ppvObject)
  code
  if self.IsEqualIID(riid, address(_IAccessible)) or |
    self.IsEqualIID(riid, address(_IDispatch)) or |
    self.IsEqualIID(riid, address(_IUnknown))
    ppvObject = address(self.IAccessible)
    self.AddRef()
    return S_OK
  end
  ppvObject = 0
  return E_NOINTERFACE

AccList.IAccessible.QueryInterface    procedure(long riid, *long ppvObject)
  code
  return self.QueryInterface(riid, ppvObject)

AccList.IAccessible.AddRef    procedure
r                               long
  code
  r = self.AddRef()
  return r

AccList.IAccessible.Release   procedure
r                               long
  code
  r = self.Release()
  return r

!--- IDispatch (stubs) -------------------------------------------------------
AccList.IAccessible.GetTypeInfoCount  procedure(*long pctinfo)
  code
  pctinfo = 0
  return S_OK

AccList.IAccessible.GetTypeInfo   procedure(long iTInfo, long lcid, long ppTInfo)
  code
  return E_NOTIMPL

AccList.IAccessible.GetIDsOfNames procedure(long riid, long prgszNames, long cNames, long lcid, long prgDispId)
  code
  return DISP_E_UNKNOWNNAME

AccList.IAccessible.Invoke    procedure(long dispIdMember, long riid, long lcid, short wFlags, long pDispParams, long pVarResult, long pExcepInfo, long puArgErr)
  code
  return DISP_E_MEMBERNOTFOUND

!--- IAccessible -------------------------------------------------------------
AccList.IAccessible.get_accParent procedure(*long ppdispParent)
  code
  ppdispParent = 0
  return S_FALSE

AccList.IAccessible.get_accChildCount procedure(*long pcountChildren)
  code
  DbgOut('get_accChildCount t=' & GetCurrentThreadId())
  !glo:Crit.Wait()
  pcountChildren = records(NameQ)
  !glo:Crit.Release()
  return S_OK

AccList.IAccessible.get_accChild  procedure(long vcA, long vcB, long vcVal, long vcD, *long ppdispChild)
  code
  ppdispChild = 0
  return S_FALSE

AccList.IAccessible.get_accName   procedure(long vcA, long vcB, long vcVal, long vcD, *long pszName)
RowTxt                              cstring(512)
bs                                  CBStr
  code
  DbgOut('get_accName child=' & vcVal & ' t=' & GetCurrentThreadId())
  pszName = 0
  !glo:Crit.Wait()
  if vcVal = 0
    RowTxt = 'Data list'
  elsif vcVal > 0 and vcVal <= records(NameQ)
    get(NameQ, vcVal)
    if ~errorcode()
      RowTxt = clip(NameQ.NName) & ', ' & clip(NameQ.NCity)
    end
  end
  !glo:Crit.Release()
  if ~RowTxt
    return S_FALSE
  end
  bs.Init(RowTxt, false)
  pszName = bs.GetBStr()
  return S_OK

AccList.IAccessible.get_accValue  procedure(long vcA, long vcB, long vcVal, long vcD, *long pszValue)
  code
  pszValue = 0
  return S_FALSE

AccList.IAccessible.get_accDescription    procedure(long vcA, long vcB, long vcVal, long vcD, *long pszDescription)
  code
  pszDescription = 0
  return S_FALSE

AccList.IAccessible.get_accRole   procedure(long vcA, long vcB, long vcVal, long vcD, long pvarRole)
v                                   like(tVariant)
  code
  DbgOut('get_accRole child=' & vcVal)
  clear(v)
  v.vt = VT_I4
  if vcVal = 0
    v.iVal = ROLE_SYSTEM_LIST
  else
    v.iVal = ROLE_SYSTEM_LISTITEM
  end
  CopyMemory(pvarRole, address(v), size(tVariant))
  return S_OK

AccList.IAccessible.get_accState  procedure(long vcA, long vcB, long vcVal, long vcD, long pvarState)
v                                   like(tVariant)
locChoice                           long
  code
  DbgOut('get_accState child=' & vcVal)
  !glo:Crit.Wait()
  locChoice = glo:CurChoice
  !glo:Crit.Release()
  clear(v)
  v.vt = VT_I4
  if vcVal = 0
    v.iVal = STATE_SYSTEM_FOCUSABLE
  else
    v.iVal = STATE_SYSTEM_SELECTABLE + STATE_SYSTEM_FOCUSABLE
    if vcVal = locChoice
      v.iVal += STATE_SYSTEM_SELECTED + STATE_SYSTEM_FOCUSED
    end
  end
  CopyMemory(pvarState, address(v), size(tVariant))
  return S_OK

AccList.IAccessible.get_accHelp   procedure(long vcA, long vcB, long vcVal, long vcD, *long pszHelp)
  code
  pszHelp = 0
  return S_FALSE

AccList.IAccessible.get_accHelpTopic  procedure(*long pszHelpFile, long vcA, long vcB, long vcVal, long vcD, *long pidTopic)
  code
  pszHelpFile = 0
  pidTopic = 0
  return S_FALSE

AccList.IAccessible.get_accKeyboardShortcut   procedure(long vcA, long vcB, long vcVal, long vcD, *long pszKeyboardShortcut)
  code
  pszKeyboardShortcut = 0
  return S_FALSE

AccList.IAccessible.get_accFocus  procedure(long pvarChild)
v                                   like(tVariant)
locChoice                           long
  code
  DbgOut('get_accFocus t=' & GetCurrentThreadId())
  !glo:Crit.Wait()
  locChoice = glo:CurChoice
  !glo:Crit.Release()
  clear(v)
  v.vt = VT_I4
  v.iVal = locChoice                               ! the focused row
  CopyMemory(pvarChild, address(v), size(tVariant))
  return S_OK

AccList.IAccessible.get_accSelection  procedure(long pvarChildren)
v                                       like(tVariant)
locChoice                               long
  code
  DbgOut('get_accSelection t=' & GetCurrentThreadId())
  !glo:Crit.Wait()
  locChoice = glo:CurChoice
  !glo:Crit.Release()
  clear(v)
  v.vt = VT_I4
  v.iVal = locChoice
  CopyMemory(pvarChildren, address(v), size(tVariant))
  return S_OK

AccList.IAccessible.get_accDefaultAction  procedure(long vcA, long vcB, long vcVal, long vcD, *long pszDefaultAction)
  code
  pszDefaultAction = 0
  return S_FALSE

AccList.IAccessible.accSelect procedure(long flagsSelect, long vcA, long vcB, long vcVal, long vcD)
  code
  return E_NOTIMPL

AccList.IAccessible.accLocation   procedure(*long pxLeft, *long pyTop, *long pcxWidth, *long pcyHeight, long vcA, long vcB, long vcVal, long vcD)
rc                                  like(RECT)
  code
  if GetWindowRect(glo:ListHWND, address(rc))
    pxLeft    = rc.left
    pyTop     = rc.top
    pcxWidth  = rc.right - rc.left
    pcyHeight = rc.bottom - rc.top
    return S_OK
  end
  return S_FALSE

AccList.IAccessible.accNavigate   procedure(long navDir, long vsA, long vsB, long vsVal, long vsD, long pvarEndUpAt)
v                                   like(tVariant)
cnt                                 long
nxt                                 long
  code
  DbgOut('accNavigate dir=' & navDir & ' start=' & vsVal & ' t=' & GetCurrentThreadId())
  !glo:Crit.Wait()
  cnt = records(NameQ)
  !glo:Crit.Release()
  nxt = 0
  case navDir
  of 7                                             ! NAVDIR_FIRSTCHILD
    nxt = choose(cnt > 0, 1, 0)
  of 8                                             ! NAVDIR_LASTCHILD
    nxt = cnt
  of 5                                             ! NAVDIR_NEXT
  orof 2                                           ! NAVDIR_DOWN
    if vsVal < cnt then nxt = vsVal + 1.
  of 6                                             ! NAVDIR_PREVIOUS
  orof 1                                           ! NAVDIR_UP
    if vsVal > 1 then nxt = vsVal - 1.
  end
  clear(v)
  if nxt > 0
    v.vt = VT_I4
    v.iVal = nxt
    CopyMemory(pvarEndUpAt, address(v), size(tVariant))
    return S_OK
  end
  v.vt = VT_EMPTY
  CopyMemory(pvarEndUpAt, address(v), size(tVariant))
  return S_FALSE

AccList.IAccessible.accHitTest    procedure(long xLeft, long yTop, long pvarChild)
v                                   like(tVariant)
rc                                  like(RECT)
  code
  clear(v)
  if GetWindowRect(glo:ListHWND, address(rc)) and xLeft >= rc.left and xLeft < rc.right |
    and yTop >= rc.top and yTop < rc.bottom
    v.vt = VT_I4
    v.iVal = 0                                     ! CHILDID_SELF
    CopyMemory(pvarChild, address(v), size(tVariant))
    return S_OK
  end
  v.vt = VT_EMPTY
  CopyMemory(pvarChild, address(v), size(tVariant))
  return S_FALSE

AccList.IAccessible.accDoDefaultAction    procedure(long vcA, long vcB, long vcVal, long vcD)
  code
  return E_NOTIMPL

AccList.IAccessible.put_accName   procedure(long vcA, long vcB, long vcVal, long vcD, long szName)
  code
  return E_NOTIMPL

AccList.IAccessible.put_accValue  procedure(long vcA, long vcB, long vcVal, long vcD, long szValue)
  code
  return E_NOTIMPL

!=============================================================================
DbgOut    procedure(string pMsg)
s           cstring(512)
  code
  s = clip(pMsg) & '<13,10>'
  OutputDebugString(s)
