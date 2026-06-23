! ============================================================================
!  AccListLink.inc  -  prototypes for the template-driven helper procedures.
!
!  Include this INSIDE a MAP (the AccBrowse template adds it to the global map
!  via %CustomGlobalMapIncludes). Implementations live in AccList.clw.
!
!    AccListAttach  - create + Init an AccListCls for a browse's list/queue
!    AccListNotify  - fire EVENT_OBJECT_FOCUS for the browse that changed row
!    AccListDetach  - Kill + release the AccListCls for a browse
!
!  ownerKey is any stable per-browse id; the template passes ADDRESS(SELF)
!  (the browse object) from inside the browse method embeds.
! ============================================================================
AccListAttach          PROCEDURE(SIGNED pFeq, *QUEUE pQ, LONG pOwnerKey)
AccListNotify          PROCEDURE(LONG pOwnerKey)
AccListDetach          PROCEDURE(LONG pOwnerKey)
