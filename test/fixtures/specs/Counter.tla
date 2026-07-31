---- MODULE Counter ----
EXTENDS Integers

VARIABLE
  \* @type: Int;
  count,
  \* @type: Str;
  lastTransition

Vars == <<count, lastTransition>>
Init == /\ count = 0 /\ lastTransition = "Initial"
Increment == /\ count < 2 /\ count' = count + 1 /\ lastTransition' = "Increment"
Decrement == /\ count = 2 /\ count' = count - 1 /\ lastTransition' = "Decrement"
Next == Increment \/ Decrement
TypeOK == /\ count \in Int
          /\ lastTransition \in {"Initial", "Increment", "Decrement"}
Spec == Init /\ [][Next]_Vars
====
