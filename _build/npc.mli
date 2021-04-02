(** Representation of the npc of the mahjong game *)

(** [t] is an npc of the game*)
type npc

(** [execute_round npc] is the action the npc takes during its turn in a
    round *)
val execute_round : npc -> unit
