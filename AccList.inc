! ============================================================================
!  AccList.inc  -  reusable MSAA / IAccessible wrapper for Clarion LIST controls
!
!  Makes a queue-bound LIST readable by screen readers (NVDA / JAWS / Narrator)
!  with no per-control code: one AccListCls instance per list, Init(?List,Queue).
!  The row text is rendered GENERICALLY from the list format (PROPLIST) + the
!  queue (WHAT), so it works on any list without knowing its columns.
!
!  Usage:
!     MyAcc &= new AccListCls
!     MyAcc.Init(?List, MyQueue)            ! in the window's setup
!     MyAcc.NameTxt = 'Customers'           ! optional accessible name
!     ...
!     of EVENT:NewSelection                 ! so SR tracks arrow keys
!       if field() = ?List then MyAcc.NotifySelection().
!     ...
!     MyAcc.Kill()                          ! before the window closes
!
!  Project: add AccList.clw and oleacc.lib.
! ============================================================================
  OMIT('_EndOfAccList_',_AccListPresent_)
_AccListPresent_  EQUATE(1)

  INCLUDE('svcom.inc'),ONCE                 ! CCOMUserObject, IDispatch, tVariant, HRESULT

! IAccessible : IDispatch.  [in] VARIANT = 4 LONGs (child id = 3rd = vcVal).
! [out] VARIANT* = a plain LONG pointer (the method writes it with CopyMemory).
IAccessible             INTERFACE(IDispatch),COM
get_accParent             PROCEDURE(*LONG ppdispParent),HRESULT
get_accChildCount         PROCEDURE(*LONG pcountChildren),HRESULT
get_accChild              PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG ppdispChild),HRESULT
get_accName               PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG pszName),HRESULT
get_accValue              PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG pszValue),HRESULT
get_accDescription        PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG pszDescription),HRESULT
get_accRole               PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, LONG pvarRole),HRESULT
get_accState              PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, LONG pvarState),HRESULT
get_accHelp               PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG pszHelp),HRESULT
get_accHelpTopic          PROCEDURE(*LONG pszHelpFile, LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG pidTopic),HRESULT
get_accKeyboardShortcut   PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG pszKeyboardShortcut),HRESULT
get_accFocus              PROCEDURE(LONG pvarChild),HRESULT
get_accSelection          PROCEDURE(LONG pvarChildren),HRESULT
get_accDefaultAction      PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, *LONG pszDefaultAction),HRESULT
accSelect                 PROCEDURE(LONG flagsSelect, LONG vcA, LONG vcB, LONG vcVal, LONG vcD),HRESULT
accLocation               PROCEDURE(*LONG pxLeft, *LONG pyTop, *LONG pcxWidth, *LONG pcyHeight, LONG vcA, LONG vcB, LONG vcVal, LONG vcD),HRESULT
accNavigate               PROCEDURE(LONG navDir, LONG vsA, LONG vsB, LONG vsVal, LONG vsD, LONG pvarEndUpAt),HRESULT
accHitTest                PROCEDURE(LONG xLeft, LONG yTop, LONG pvarChild),HRESULT
accDoDefaultAction        PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD),HRESULT
put_accName               PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, LONG szName),HRESULT
put_accValue              PROCEDURE(LONG vcA, LONG vcB, LONG vcVal, LONG vcD, LONG szValue),HRESULT
                        END

AccListCls              CLASS(CCOMUserObject),IMPLEMENTS(IAccessible),TYPE,MODULE('AccList.clw'),LINK('AccList.clw')
Init                      PROCEDURE(LONG pFeq, *QUEUE pQ)
Kill                      PROCEDURE
NotifySelection           PROCEDURE                                   ! call on EVENT:NewSelection
NameTxt                   CSTRING(128)                                ! optional accessible name of the list
Feq                       LONG
hWnd                      LONG
OldProc                   LONG
OwnerKey                  LONG                                        ! stable id used by the template helpers (ADDRESS of the browse)
Q                         &QUEUE
QueryInterface            PROCEDURE(LONG riid, *LONG ppvObject),HRESULT,DERIVED
RowCount                  PROCEDURE(),LONG,PROTECTED
CurRow                    PROCEDURE(),LONG,PROTECTED
RowText                   PROCEDURE(LONG pRow),STRING,PROTECTED        ! GENERIC row renderer
                        END
  _EndOfAccList_
