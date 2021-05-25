open Players
open Tiles
open Command

type t = {
  house : player;
  house_seat : int;
  players : Players.t;
  mutable current_drawer : int;
  mutable tiles_count_left : int;
  hands : Tiles.t array;
  hands_open : Tiles.t array;
  mutable tiles_left : Tiles.t;
  mutable tiles_played : Tiles.t;
  mutable current_discard : Tiles.tile;
  kong_records : int array;
  mutable turn : int;
}

type round_end_message = {
  winner : Players.player option;
  losers : Players.player option;
  score : int;
}

(* [end_with_draw] is a round end message with draw conditions *)
let end_with_draw : round_end_message =
  { winner = None; losers = None; score = 0 }

(* exception [End_of_tiles] is thrown when there are no more tiles in
   the current round *)
exception End_of_tiles

(* exception [Quit_game] is thrown when the round is quit *)
exception Quit_game

(* exception [Restart_round] is thrown when the current round is to be
   restarted *)
exception Restart_round

(* exception [Help_needed t] is thrown when user asked for help *)
exception Help_needed of t

(* exception [Invalid s] is thrown when a provided string [s] is invalid *)
exception Invalid of string

(* exception [Winning message] is thrown when the round terminates and a
   message is carried to the parent stack *)
exception Winning of round_end_message

type result =
  | Quit_game
  | Unknown_exception of string
  | Round_end of round_end_message

let is_draw (res : result) : bool =
  match res with
  | Quit_game -> false
  | Round_end t -> (
      match t.winner with None -> true | Some t -> false)
  | Unknown_exception _ -> false

(* [locate_player players index] is the player at the [index] in a list
   of four players [players]*)
let locate_player players index = List.nth players index

(* [player_int state i] is the player at index [i] in [state] *)
let player_int state (index : int) =
  player_to_string (locate_player state.players index)

(** [kong_draw_one RoundState.t int] representing in the game where a
    player kong anyone's tile, they need to draw one tile form the wall.
    Requires: the state to be a valid state, and int to be a valid
    representation of a player. Mutation: draw one tile for the player
    who kongs. The state is mutated to be an valid state.

    @return [unit] *)
let rec kong_draw_one state (konger_index : int) : unit =
  match state.tiles_left with
  | [] -> raise End_of_tiles
  | h :: t ->
      state.tiles_count_left <- state.tiles_count_left - 1;
      state.tiles_left <- t;
      if Tiles.is_bonus h then (
        (* redraw a tile when the draw is bonus *)
        state.hands_open.(konger_index) <-
          add_tile_to_hand h state.hands_open.(konger_index);
        kong_draw_one state konger_index;
        ())
      else
        state.hands.(konger_index) <-
          add_tile_to_hand h state.hands.(konger_index);
      ()

(** [draw_one RoundState.t] representing in the game where a player is
    in turn to draw, they need to draw one tile form the wall. Requires:
    the state to be a valid state. Mutation: draw one tile for the
    player who comes next. The state is mutated to be an valid state.

    @return [unit] *)
let rec draw_one state =
  match state.tiles_left with
  | [] -> raise End_of_tiles
  | h :: t ->
      state.tiles_count_left <- state.tiles_count_left - 1;
      state.tiles_left <- t;
      if Tiles.is_bonus h then (
        (* redraw a tile when the draw is bonus *)
        state.hands_open.(state.current_drawer) <-
          add_tile_to_hand h state.hands_open.(state.current_drawer);
        draw_one state;
        ())
      else (
        state.hands.(state.current_drawer) <-
          add_tile_to_hand h state.hands.(state.current_drawer);
        state.current_drawer <- (state.current_drawer + 1) mod 4;
        state.turn <- state.turn + 1;
        ())

(** [skip_to_after RoundState.t Players.t] representing in the game
    where the turn of the game need to be change, which is usually after
    anykong chow, kong, or punged. Who draw next wil be set accordingly.
    Requires: the state to be a valid state. Mutation: change the
    current drawer. The state is mutated to be an valid state.

    @return [unit] *)
let skip_to_after state player =
  let rec pos player acc = function
    | h :: t -> if h = player then acc else pos player (acc + 1) t
    | [] -> failwith "precondition violation"
  in
  state.current_drawer <- pos player 0 state.players + 1

(** [view_played RoundState.t] representing in the game where the player
    request to see all the tiles played. No change can be made to the
    state representation. Requires: the state to be a valid
    representation of game.

    @return [unit] *)
let view_played (state : t) : unit =
  Unix.sleep 1;
  print_endline "Here is the current discard:";
  print_string (tile_string_converter state.current_discard);
  print_endline "\nHere are all the tiles played:";
  print_str_list (tiles_to_str state.tiles_played);
  print_endline "\nHere are player's open hand:";
  print_string "Ian:[ ";
  print_str_list (tiles_to_str state.hands_open.(1));
  print_string " ];\nLeo:[ ";
  print_str_list (tiles_to_str state.hands_open.(2));
  print_string " ];\nAndrew:[ ";
  print_str_list (tiles_to_str state.hands_open.(3));
  print_string " ].";
  ()

(** [print_player_hand RoundState.t] representing in the game where we
    show the player what is their current hand. No change can be made to
    the state representation. Note that this is for printing of the
    [user]'s hand, not the [npc]'s hands. Requires: the state to be a
    valid representation of game.

    @return [unit] *)
let print_player_hand state : unit =
  print_str_list (tiles_to_str state.hands.(0));
  print_string " }:  { ";
  print_str_list (tiles_to_str state.hands_open.(0));
  ()

(** [scan ()] scan the input line, and then parse that string into a
    command representation. the return type should not contain any
    exceptions and should be in the form of @return [Command.command] *)
let rec scan () =
  print_string "> ";
  match parse (read_line ()) with
  | exception Command.Invalid str ->
      print_endline str;
      scan ()
  | exception _ ->
      print_endline "/unknown exception was caught. Please retry:";
      scan ()
  | t -> t

(** [user_discard RoundState.t] representing in the game where the user
    needs to discard one of the tiles that they currently holds. One
    change must be made to the state representation where the user's
    hand is get rid of one of the tile to discard. Note that this is for
    discard of the [user]'s hand, not the [npc]'s hands. Requires: the
    state to be a valid representation of game.

    @return [unit] *)
let user_discard state (index : int) =
  let user_index = 0 in
  let discard_option =
    List.nth_opt state.hands.(user_index) (index - 1)
  in
  let discard =
    match discard_option with
    | None ->
        raise
          (Invalid
             "This discard index is invalid. Please check your hand \
              length.")
    | Some t -> t
  in
  state.hands.(user_index) <- remove state.hands.(user_index) discard 1;
  state.tiles_played <- discard :: state.tiles_played;
  state.current_discard <- discard;
  ()

(** [user_discard RoundState.t] representing in the game where the user
    or the npc is winning the round. The game will ends and return a
    message carring who wins the game and the score the they wins. Note
    that this is for winning of a round, not draw of a round. The round
    is break by raising an [exception] This exception will then be
    handled to provide a valid round_end message. Requires: the state to
    be a valid representation of game.

    @return [unit] and [exception] *)
let win_round
    (state : t)
    (player : Players.player)
    (from_player : Players.player)
    (dekong_score : int) : unit =
  let same_player = player = from_player in
  let winning_round_end_message =
    {
      winner = Some player;
      losers = (if same_player then None else Some from_player);
      score = dekong_score + state.kong_records.(0);
    }
  in
  raise (Winning winning_round_end_message)

(** [discard_hint RoundState.t] represent when the player request to see
    a hint to discard. The hint is determined based on function
    implemented in [tiles.ml] No change can be made to the state
    representation. Requires: the state to be a valid representation of
    game.

    @return [unit] *)
let discard_hint state =
  (* check hu *)
  if hu_possible state.hands.(0) then print_endline "you can [hu]!"
  else if (* check kong *)
          kong_possible state.hands.(0) then
    print_endline "you can [kong]"
  else
    let discard_suggestion_tile = discard_suggestion state.hands.(0) in
    (* give discard suggestions *)
    print_string "We suggest you discard: ";
    print_endline (tile_string_converter discard_suggestion_tile)

(** [continue_hint RoundState.t] represent when the player request to
    see a hint to continue the game. The hint is determined based on
    function implemented in [tiles.ml] No change can be made to the
    state representation. Requires: the state to be a valid
    representation of game.

    @return [unit] *)
let continue_hint state =
  (* let pung_possible is implemented in tiles.ml *)
  let continue_prompt () =
    print_endline
      "Nothing you can do for this turn. Enter [continue] to continue"
  in
  if
    add_tile_to_hand state.current_discard state.hands.(0)
    |> hu_possible
  then print_endline "you can [hu]!"
  else if
    (* check pung *)
    pung_possible state.hands.(0) state.current_discard
  then print_endline "you can [pung]"
  else if state.current_drawer = 0 then (
    (* check chow *)
    match chow_possible state.hands.(0) state.current_discard with
    | None -> continue_prompt ()
    | Some (tile_s1, tile_s2) ->
        print_string "you can [chow]: ";
        print_string (tile_string_converter tile_s1 ^ " ");
        print_endline (tile_string_converter tile_s2))
  else continue_prompt ()

(** [continue_hint RoundState.t] represent when the player request to
    see help. The help is first seperate into whether the player is
    about to discard or continue the game, and then redirected to helper
    functions. No change can be made to the state representation.
    Requires: the state to be a valid representation of game.

    @return [unit] *)
let resolve_help state =
  ANSITerminal.print_string [ ANSITerminal.red ]
    "To phrase a command, please begin with Discard, Continue, Chow, \
     Pung, Kong, Quit, Help, Restart, Mahjong, and Played\n";
  if state.current_drawer = 1 then
    (* current player is user *)
    discard_hint state
  else (* current player is npc *)
    continue_hint state

(**********************************************************************
  Begin take command function
  ************************************************************)

(** [player_discard RoundState.t] represent when the player will discard
    a tile. The help is first seperate into whether the player is
    request for help. This function also handle for exception of invalid
    discard index. Then it call for helper function to discard the tile.
    Requires: the state to be a valid representation of game.

    @return [unit] *)
let rec player_discard state : unit =
  print_string "{ ";
  print_player_hand state;
  print_endline " }\nPlease discard one";
  match take_command state (scan ()) with
  | exception Help_needed t ->
      resolve_help t;
      player_discard state
  | exception Tiles.Invalid_index -> player_discard state
  | exception Invalid str ->
      print_endline str;
      player_discard state
  | exception exn ->
      Unix.sleepf 0.1;
      raise exn
  | () ->
      Unix.sleepf 0.2;
      ()

(** [take_command RoundState.t Command.command] represent when the
    player when the scanner has provide a player's command. Apply
    pattern match to the command and deal with most of the commands in
    helper functions. When a game need to be ended, a exception is raise
    and then return to main menu. If the round need to be ended, an
    exception is raised and the end_round messsage is provided. If help
    or played is needed, exception is raised to handle the player
    request. Requires: the state to be a valid representation of game,
    and the command to be a valid command.

    @return [unit] *)
and take_command state command =
  let is_users_turn = state.current_drawer = 1 in
  match command with
  (* anytime, valid *)
  | Quit -> raise Quit_game
  | Restart -> raise Restart_round
  | Help -> raise (Help_needed state)
  | Played ->
      view_played state;
      raise (Invalid "\n====================")
  | Next -> raise End_of_tiles
  (* anytime, check *)
  | Mahjong -> user_mahjong state is_users_turn
  | Kong -> initialize_kong state is_users_turn
  (* player only, check *)
  | Discard int ->
      if is_users_turn then user_discard state int
      else raise (Invalid "It is not your turn to discard")
  (* npc only, check *)
  | Continue ->
      if not is_users_turn then ()
      else raise (Invalid "must take action")
  | Pung -> initialize_pung state is_users_turn
  | Chow (index_1, index_2) -> initialize_chow state index_1 index_2

(** [initialize_pung state is_users_turn] represents when the
    [take_command RoundState.t Command.command] met a pung command. It
    then goes to specific cases according to the situation of the pung.
    Requires: the state to be a valid representation of game.

    @return [unit] *)
and initialize_pung state is_users_turn =
  if is_users_turn then
    raise (Invalid "you can only pung other's tiles")
  else if pung_valid state.hands.(0) state.current_discard then
    user_pung state
  else raise (Invalid "this discard is not valid to pung")

(** [user_selfkong state] represents when the
    [take_command RoundState.t Command.command] met a kong command at
    self_kong situation. It then edit the state accordingly. Requires:
    the state to be a valid representation of game.

    @return [unit] *)
and user_selfkong state =
  let user_index = 0 in
  let self_kong =
    selfkong_tile state.hands_open.(user_index) state.hands.(user_index)
  in
  state.hands_open.(user_index) <-
    add_tile_to_hand self_kong state.hands_open.(user_index);
  state.hands.(user_index) <-
    remove state.hands.(user_index) self_kong 1;
  state.kong_records.(user_index) <- state.kong_records.(user_index) + 1;
  kong_draw_one state 0;
  player_discard state;
  ()

(** [user_ankong state] represents when the
    [take_command RoundState.t Command.command] met a kong command at
    an_kong situation. It then goes to specific cases according to the
    situation of the pung. Requires: the state to be a valid
    representation of game.

    @return [unit] *)
and user_ankong state =
  let ankong =
    match ankong_tile_opt state.hands.(0) with
    | None ->
        failwith "precondition violation at user ankong at roundstate"
    | Some t -> t
  in
  let user_index = 0 in
  state.hands.(user_index) <- remove state.hands.(user_index) ankong 4;
  state.hands_open.(user_index) <-
    ankong :: ankong :: ankong :: ankong
    :: state.hands_open.(user_index);
  state.kong_records.(user_index) <- state.kong_records.(user_index) + 2;
  kong_draw_one state 0;
  player_discard state;
  ()

(** [user_kong state] represents when the
    [take_command RoundState.t Command.command] met a kong command at
    user_kong situation. It then goes to specific cases according to the
    situation of the pung: in the following sequence to round state:
    move discard to user's open hand. move three discard - same card to
    open hand. set current discard to blank. Requires: the state to be a
    valid representation of game.

    @return [unit] *)
and user_kong state =
  let kong = state.current_discard in
  let user_index = 0 in
  state.hands_open.(user_index) <-
    kong :: kong :: kong :: kong :: state.hands_open.(user_index);
  state.hands.(user_index) <- remove state.hands.(user_index) kong 3;
  state.current_discard <- Blank;
  state.kong_records.(user_index) <- state.kong_records.(user_index) + 1;
  kong_draw_one state 0;
  skip_to_after state (List.hd state.players);
  player_discard state;
  ()

(** [user_pung state] represents when the
    [take_command RoundState.t Command.command] met a pung command at
    user_pung situation. It then goes to specific cases according to the
    situation of the pung: in the following sequence to round state:
    move discard to user's open hand. move two discard - same card to
    open hand. set current discard to blank. Requires: the state to be a
    valid representation of game.

    @return [unit] *)
and user_pung state =
  let pung = state.current_discard in
  let user_index = 0 in
  state.hands_open.(user_index) <-
    pung :: pung :: pung :: state.hands_open.(user_index);
  state.hands.(user_index) <- remove state.hands.(user_index) pung 2;
  state.current_discard <- Blank;

  skip_to_after state (List.hd state.players);
  player_discard state;
  ()

(** [user_chow state] represents when the
    [take_command RoundState.t Command.command] met a chow command at
    user_chow situation. It then goes to specific cases according to the
    situation of the pung: in the following sequence to round state:
    move discard to user's open hand. move two discard - same card to
    open hand. set current discard to blank. Requires: the state to be a
    valid representation of game.

    @return [unit] *)
and user_chow state index_1 index_2 =
  let chow = state.current_discard in
  let user_index = 0 in
  let first_tile = List.nth state.hands.(user_index) (index_1 - 1) in
  let second_tile = List.nth state.hands.(user_index) (index_2 - 1) in
  state.hands_open.(user_index) <-
    first_tile :: second_tile :: chow :: state.hands_open.(user_index);
  state.hands.(user_index) <-
    chow_remove state.hands.(user_index) index_1 index_2;
  state.current_discard <- Blank;

  skip_to_after state (List.hd state.players);
  player_discard state;
  ()

(** [user_mahjong state] represents when the
    [take_command RoundState.t Command.command] met a mahjong command at
    any situation. It determine if the hand is valid to mahjong. If is,
    then the round will end with an exception of the winning_message.
    Else, the game continue. Requires: the state to be a valid
    representation of game.

    @return [unit] *)
and user_mahjong state is_users_turn =
  let user = List.hd state.players in
  if is_users_turn then
    if winning_valid state.hands.(0) state.hands_open.(0) None then
      win_round state user
        (List.nth state.players 0)
        (scoring state.hands.(0) state.hands_open.(0) None)
    else raise (Invalid "your hand does not meet mahjong requirement")
  else if
    winning_valid state.hands.(0) state.hands_open.(0)
      (Some state.current_discard)
  then
    win_round state user
      (List.nth state.players (state.current_drawer - 1))
      (scoring state.hands.(0) state.hands_open.(0)
         (Some state.current_discard))
  else raise (Invalid "this discard is not valid to hu")

(** [initialize_kong state is_users_turn] represents when the
    [take_command RoundState.t Command.command] met a kong command. It
    then goes to specific cases according to the situation of the kong.
    Requires: the state to be a valid representation of game.

    @return [unit] *)
and initialize_kong state is_users_turn =
  if is_users_turn then
    if selfkong_valid state.hands_open.(0) state.hands.(0) then
      user_selfkong state
    else if ankong_valid_new state.hands.(0) then user_ankong state
    else raise (Invalid "this discard is not valid to kong")
  else if kong_valid state.hands.(0) state.current_discard then
    user_kong state
  else raise (Invalid "this discard is not valid to kong")

(** [initialize_chow state is_users_turn] represents when the
    [take_command RoundState.t Command.command] met a chow command. It
    then goes to specific cases according to the situation of the chow.
    Requires: the state to be a valid representation of game.

    @return [unit] *)
and initialize_chow state index_1 index_2 =
  let is_upper_turn = state.current_drawer = 0 in
  if not is_upper_turn then
    raise (Invalid "you can only chow your upper hand's tiles")
  else if
    match
      chow_index_valid state.hands.(0) index_1 index_2
        state.current_discard
    with
    | exception Tiles.Invalid_index ->
        raise
          (Invalid "index must be positive and bounded by hand length")
    | t -> t
  then user_chow state index_1 index_2
  else raise (Invalid "this discard is not valid to chow")

(**********************************************************************
  End take command function
  ************************************************************)

let init_round input_house input_players : t =
  let rec house_pos acc = function
    | h :: t -> if h = input_house then acc else house_pos (acc + 1) t
    | _ -> failwith "precondition violation"
  in
  let rec helper n state =
    match n with
    | 0 -> state
    | _ ->
        draw_one state;
        helper (n - 1) state
  in
  let house_seat_int = house_pos 0 input_players in
  helper 52
    {
      house = input_house;
      house_seat = house_seat_int;
      players = input_players;
      current_drawer = house_seat_int;
      tiles_count_left = tile_length (init_tiles ());
      hands = [| []; []; []; [] |];
      hands_open = [| []; []; []; [] |];
      tiles_left = init_tiles ();
      tiles_played = [];
      current_discard = Blank;
      kong_records = [| 0; 0; 0; 0 |];
      turn = -51;
    }

let hand index t = tiles_to_str t.hands.(index)

let tiles_left t = tiles_to_str t.tiles_left

(** [npc_response state] representating the npc respoding to the
    player's discard. In the easy mode, there will be no action. In the
    advanced mode, the npc may chow if valid, and may hu if valid.
    Requires: the state to be a valid representation of game.

    @return [unit] *)
let npc_response state : unit =
  print_endline "No player responded to your discard";
  Unix.sleepf 0.5;
  ()

(** [npc_discard state] representating the npc respoding to the player's
    discard. In the easy mode, npc will discard randomly. In the
    advanced mode, the npc will discard according to algorithm.
    Requires: the state to be a valid representation of game.

    @return [unit] *)
let npc_discard state index : unit =
  let assoc =
    if index = 2 then separate_last_tile state.hands.(index)
    else separate_random_tile state.hands.(index)
  in
  let discard = snd assoc in
  state.hands.(index) <- fst assoc;
  state.current_discard <- discard;
  state.tiles_played <- discard :: state.tiles_played;
  (* print_string ("Player " ^ string_of_int index ^ " "); *)
  print_string (player_int state index);
  print_string " has discarded: ";
  print_endline (tile_string_converter discard);
  ()

(** [player_response state npc_player_index] representating the respond
    to the npc's discard. Take command from scanner and then deal with
    the command. Requires: the state to be a valid representation of
    game, and the index to be a valid representation of the player.

    @return [unit] *)
let rec player_response state index : unit =
  print_string "{ ";
  print_player_hand state;
  print_endline " }";
  print_string "Please respond to ";
  print_endline (player_int state index);
  match take_command state (scan ()) with
  | exception Tiles.Invalid_index ->
      print_endline
        "Invalid Index to use. Please check your length of hand";
      player_response state index
  | exception Invalid str ->
      print_endline str;
      player_response state index
  | exception Help_needed t ->
      resolve_help t;
      player_response state index
  | exception exn -> raise exn
  | () -> ()

(** [user_round state] representating the execution of a use's round.
    Requires: the state to be a valid representation of game.

    @return [unit] *)
let rec user_round state : unit =
  let turn =
    if state.turn < 85 then string_of_int state.turn else "end"
  in
  print_endline ("\nTurn " ^ turn);
  draw_one state;
  player_discard state;
  npc_response state;
  find_round state

(** [npc_int_round state npc_int] representating the execution of a
    use's round. Requires: the state to be a valid representation of
    game, and the index to be a valid representation of the player.

    @return [unit] *)
and npc_int_round state npc_int : unit =
  let turn =
    if state.turn < 85 then string_of_int state.turn else "end"
  in
  print_endline ("\nTurn " ^ turn);
  draw_one state;
  npc_discard state npc_int;
  player_response state npc_int;
  find_round state

(** [find_round state] representating the determination of who is the
    house and thus will begin the game. Requires: the state to be a
    valid representation of game, and the index to be a valid
    representation of the player.

    @return [unit] *)
and find_round state : unit =
  if state.current_drawer = 0 then user_round state
  else npc_int_round state state.current_drawer

(** [round_end_message message] prints the appropriate post round
    message according to [message] *)
let round_end_message message =
  match message.winner with
  | None ->
      print_endline "\nRan out of Tiles! Game end in Draw\n";
      Unix.sleep 2
  | Some player ->
      (let verb = if player = User then " are" else " is" in
       print_endline
         ("\n" ^ player_to_string player ^ verb
        ^ " this Round's Winner!\n");
       match message.losers with
       | None ->
           print_endline "Everyone Else Loses!\n";
           Unix.sleep 2
       | Some loser ->
           print_endline (player_to_string loser ^ " Loses!\n"));
      Unix.sleep 2

let rec start_rounds input_house input_players =
  let init_state = init_round input_house input_players in
  start_rounds_loop init_state input_house

(** [start_round_loop state house] starts the loop to carry out the
    current mahjong round *)
and start_rounds_loop state input_house : result =
  ANSITerminal.print_string
    [ ANSITerminal.red; ANSITerminal.Bold ]
    "Remerber, to phrase a command, please begin with Discard, \
     Continue, Chow, Pung, Kong, Quit, Help, Restart, Mahjong, and \
     Played.\n\n";
  ANSITerminal.print_string
    [ ANSITerminal.red; ANSITerminal.Bold ]
    "If you choose to not to respond to other's discard, simply hit \
     enter.\n\n";
  ANSITerminal.print_string
    [ ANSITerminal.red; ANSITerminal.Bold ]
    "To discard a tile at your turn, simply enter the index of the \
     tile (starting at 1).\n\n";
  print_endline ("The House is: " ^ player_to_string input_house);
  print_string "\nGood luck with your draw:\n{ ";
  print_player_hand state;
  print_endline " }\n";
  start_round_helper state

(** [start_round_helper state] matches the termination of a round with
    the according response *)
and start_round_helper state =
  match find_round state with
  | exception Quit_game -> game_quit ()
  | exception Restart_round -> restart_game state
  | exception End_of_tiles -> end_of_tile ()
  | exception Winning message -> winning message
  | exception Failure mes -> failure mes
  | exception _ ->
      Unknown_exception
        "☣ Unknown Fatal Exception Caught.\n\
         Please report this exception to the authors. \n\
         Return to Main Menu."
  | () ->
      Unknown_exception
        "precondition vilation at start_round of roundstate"

(** [game_quit ()] quit the current round *)
and game_quit () =
  print_endline "\nGame Quit!\n";
  Unix.sleep 2;
  Quit_game

(** [restart_game ()] restart the current round *)
and restart_game state =
  print_endline "\nRestart Game!\n";
  Unix.sleep 2;
  start_rounds state.house state.players

(** [end_of_tile ()] end the current round with a draw*)
and end_of_tile () =
  round_end_message end_with_draw;
  Unix.sleep 2;
  Round_end end_with_draw

(** [winning message] quits the round with a message about the winner,
    loser, and score, which are stored in [message] *)
and winning message =
  round_end_message message;
  Unix.sleep 2;
  Round_end message

(** [failure mes] quits the current round with a failure mes*)
and failure mes =
  print_endline
    ("☣ Unknown Fatal Exception Caught: " ^ mes
   ^ " Please report this exception to the authors. ☣");
  Round_end end_with_draw
