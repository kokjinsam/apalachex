---- MODULE Violation ----
EXTENDS Integers

VARIABLE
  \* @type: Int;
  count,
  \* @type: Str;
  lastTransition

Vars == <<count, lastTransition>>
Init == /\ count = 0 /\ lastTransition = "Initial"
Increment == /\ count < 2 /\ count' = count + 1 /\ lastTransition' = "Increment"
Next == Increment
Unsafe == count < 1
Spec == Init /\ [][Next]_Vars
====
