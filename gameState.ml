open Players
open RoundState

type t = {
  round_num : int;
  termination_round : int;
  scores : int array;
  players : player list;
  house : player;
  house_streak : int;
  house_index : int;
  round : result;
}

type game_progress =
  | Quit
  | Continue of t

let current_round t = t.round

let locate_player players index = List.nth players index

let index_of_player player_list player =
  let rec helper players_list acc =
    match players_list with
    | [] -> failwith "precondition violation"
    | h :: t -> if h = player then acc else helper t (acc + 1)
  in
  helper player_list 0

let random_house_index = (Unix.time () |> int_of_float) mod 4

let players is_advanced =
  if is_advanced then adv_players else basic_players

let init_game (distance : int) (is_advanced : bool) : t =
  let players = players is_advanced in
  let house_index = random_house_index in
  let house = locate_player players house_index in
  {
    round_num = 0;
    termination_round = distance;
    scores = [| 5000; 5000; 5000; 5000 |];
    players;
    house;
    house_index;
    house_streak = 0;
    round = start_rounds house players;
  }

(****************************************************)
(* Functions for deciding whether the game continues or end after a
   round terminated. Updating game state accordingly if game hasn't
   ended *)
(****************************************************)

let calculate_score t house winner =
  let base_score = 3 in
  let house_bonus = if house = winner then t.house_streak + 1 else 0 in
  (base_score + house_bonus) * 100

let update_score t house winner losers tile_score =
  let winner_index = index_of_player t.players winner in
  let score = calculate_score t house winner + tile_score in
  t.scores.(winner_index) <- t.scores.(winner_index) + score;
  match losers with
  | None ->
      Array.iteri
        (fun i s ->
          if i = winner_index then ()
          else t.scores.(i) <- t.scores.(i) - score)
        t.scores
  | Some loser ->
      let loser_index = index_of_player t.players loser in
      t.scores.(loser_index) <- t.scores.(loser_index) - score

let reached_termination t house_wins =
  t.round_num = t.termination_round && not house_wins

let continue_or_quit t house house_wins =
  if reached_termination t house_wins then Quit
  else
    let new_round_number =
      if house_wins then t.round_num else t.round_num + 1
    in
    let new_house_index =
      if house_wins then t.house_index else (t.house_index + 1) mod 4
    in
    let new_house_wins = if house_wins then t.house_streak + 1 else 0 in
    let new_house = locate_player t.players new_house_index in
    Continue
      {
        t with
        round_num = new_round_number;
        house_index = new_house_index;
        house = new_house;
        house_streak = new_house_wins;
        round = start_rounds new_house t.players;
      }

let update_game_state t winning_message =
  let house = locate_player t.players t.house_index in
  match winning_message.winner with
  | None ->
      let house_wins = false in
      continue_or_quit t house house_wins
  | Some winner ->
      let tile_score = winning_message.score in
      let house_wins = house = winner in
      update_score t house winner winning_message.losers tile_score;
      continue_or_quit t house house_wins

let get_score t = t.scores

let rec update t =
  match t.round with
  | Quit_game -> get_score t
  | Round_end winning_message -> (
      match update_game_state t winning_message with
      | Continue new_state -> update new_state
      | Quit -> get_score t)
  | Unknown_exception str ->
      print_endline str;
      get_score t
