#TEMPLATE(AccBrowse, 'Accessible Lists - MSAA accessibility for Clarion browses'), FAMILY('ABC')
#!============================================================================
#! AccBrowse.tpl - global extension that makes EVERY ABC browse list readable
#! by screen readers (NVDA / JAWS / Narrator) for WCAG / Section 508.
#!
#! HOW IT WORKS
#!   Each ABC browse already generates its own derived BrowseClass with embed
#!   points for its methods. This extension injects three additive lines into
#!   those existing methods (no base-class derivation, so it does NOT clash with
#!   translation / resize / other tools that already derive BrowseClass):
#!
#!     Init             -> AccListAttach(ListBox, Q, ADDRESS(SELF))
#!     TakeNewSelection -> AccListNotify(ADDRESS(SELF))
#!     Kill             -> AccListDetach(ADDRESS(SELF))
#!
#!   In the browse's Init the list FEQ (ListBox) and queue (Q) are method
#!   parameters; ADDRESS(SELF) is the browse object - a stable key reused across
#!   all three methods so the helpers find the right list. The runtime work is
#!   in AccList.clw / AccList.inc (the AccListCls / IAccessible object).
#!
#! PROJECT REQUIREMENTS (add once)
#!   * AccList.inc, AccList.clw, AccListLink.inc on the project's source path
#!     (AccList.clw is auto-linked via LINK() in AccList.inc).
#!   * oleacc.lib in the project libraries.
#!   * Project defines:  _svLinkMode_=>1;_svDllMode_=>0
#!============================================================================
#!
#EXTENSION(AccessibleBrowses, 'Accessible Lists - all browses (MSAA / screen readers)'), APPLICATION
#DISPLAY('Adds MSAA / IAccessible support to EVERY ABC browse so that NVDA,')
#DISPLAY('JAWS and Narrator can read the list rows (WCAG / Section 508).')
#DISPLAY('')
#DISPLAY('Additive embed code only - it does NOT derive BrowseClass, so it is')
#DISPLAY('compatible with translation / resize tools that already derive it.')
#DISPLAY('')
#DISPLAY('Project must also contain AccList.inc, AccList.clw, AccListLink.inc,')
#DISPLAY('oleacc.lib, and the defines  _svLinkMode_=>1;_svDllMode_=>0')
#BOXED('Accessible Lists')
#PROMPT('&Enable accessible browses', CHECK), %AccEnabled, DEFAULT(1), AT(10)
#ENDBOXED
#!
#! ---- make the class + helper prototypes visible to the whole app ----
#AT(%CustomGlobalDeclarations), WHERE(%AccEnabled), DESCRIPTION('Accessible Lists - includes')
INCLUDE('AccList.inc'), ONCE
  #ADD(%CustomGlobalMapIncludes, 'AccListLink.INC')
#ENDAT
#!
#! ---- create one accessibility object per browse, where the browse is built ----
#AT(%BrowserMethodCodeSection), PRIORITY(8600), WHERE(%AccEnabled AND UPPER(%pClassMethod) = 'INIT' AND %pClassMethodPrototype = '(SIGNED ListBox,*STRING Posit,VIEW V,QUEUE Q,RelationManager RM,WindowManager WM)'), DESCRIPTION('Accessible Lists - attach this browse')
AccListAttach(ListBox, Q, ADDRESS(SELF))                            #! ListBox = list FEQ, Q = browse queue
#ENDAT
#!
#! ---- tell the screen reader the focused row changed ----
#AT(%BrowserMethodCodeSection), PRIORITY(5500), WHERE(%AccEnabled AND UPPER(%pClassMethod) = 'TAKENEWSELECTION' AND %pClassMethodPrototype = '()'), DESCRIPTION('Accessible Lists - announce new row')
AccListNotify(ADDRESS(SELF))
#ENDAT
#!
#! ---- tear down before the browse / window dies ----
#AT(%BrowserMethodCodeSection), PRIORITY(2000), WHERE(%AccEnabled AND UPPER(%pClassMethod) = 'KILL' AND %pClassMethodPrototype = '()'), DESCRIPTION('Accessible Lists - detach this browse')
AccListDetach(ADDRESS(SELF))
#ENDAT
