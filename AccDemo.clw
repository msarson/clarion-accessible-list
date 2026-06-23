  PROGRAM
! ============================================================================
!  AccDemo.clw  -  demonstrates the reusable AccListCls on TWO lists with
!  different queue schemas (string columns vs numeric/decimal columns),
!  proving the generic renderer and the multi-control HWND registry.
!
!  Project: AccDemo.clw + AccList.clw, plus oleacc.lib in the libraries.
! ============================================================================
  INCLUDE('AccList.inc'),ONCE

  MAP
  END

PeopleQ                QUEUE
PName                    STRING(40)
PCity                    STRING(30)
                       END

PartQ                  QUEUE
PartNo                   LONG
PartDesc                 STRING(50)
Price                    DECIMAL(9,2)
                       END

Acc1                   &AccListCls
Acc2                   &AccListCls

Win                    WINDOW('Two Accessible Lists'),AT(,,330,210),SYSTEM,GRAY,FONT('Segoe UI',9)
                         LIST,AT(8,8,150,178),USE(?People),FROM(PeopleQ),VSCROLL, |
                           FORMAT('80L(2)|M~Name~@s40@66L(2)|M~City~@s30@')
                         LIST,AT(166,8,156,178),USE(?Parts),FROM(PartQ),VSCROLL, |
                           FORMAT('34R(2)|M~Part~@n5@84L(2)|M~Description~@s50@36R(2)|M~Price~@n8.2@')
                         BUTTON('Close'),AT(143,190,44,14),USE(?CloseBtn),STD(STD:Close)
                       END

  CODE
  PeopleQ.PName = 'Alice Brown' ; PeopleQ.PCity = 'London'   ; ADD(PeopleQ)
  PeopleQ.PName = 'Carlos Diaz' ; PeopleQ.PCity = 'Madrid'   ; ADD(PeopleQ)
  PeopleQ.PName = 'Emma Foster' ; PeopleQ.PCity = 'New York' ; ADD(PeopleQ)
  PeopleQ.PName = 'Hiro Tanaka' ; PeopleQ.PCity = 'Tokyo'    ; ADD(PeopleQ)

  PartQ.PartNo = 101 ; PartQ.PartDesc = 'Hex Bolt M6'   ; PartQ.Price = 0.12  ; ADD(PartQ)
  PartQ.PartNo = 102 ; PartQ.PartDesc = 'Washer 6mm'    ; PartQ.Price = 0.04  ; ADD(PartQ)
  PartQ.PartNo = 250 ; PartQ.PartDesc = 'Bearing 608ZZ' ; PartQ.Price = 1.95  ; ADD(PartQ)
  PartQ.PartNo = 990 ; PartQ.PartDesc = 'Drive Belt'    ; PartQ.Price = 14.50 ; ADD(PartQ)

  OPEN(Win)

  Acc1 &= NEW AccListCls                              ! one instance per list
  Acc1.Init(?People, PeopleQ)
  Acc1.NameTxt = 'People'

  Acc2 &= NEW AccListCls
  Acc2.Init(?Parts, PartQ)
  Acc2.NameTxt = 'Parts'

  ACCEPT
    CASE EVENT()
    OF EVENT:NewSelection                             ! tell the SR the focus moved
      CASE FIELD()
      OF ?People ; Acc1.NotifySelection()
      OF ?Parts  ; Acc2.NotifySelection()
      END
    END
  END

  Acc1.Kill()
  Acc2.Kill()
  CLOSE(Win)
