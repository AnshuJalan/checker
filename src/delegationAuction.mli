open TokenTypes

type delegation_auction

val delegation_auction_empty : delegation_auction

val delegation_auction_touch : delegation_auction -> delegation_auction

(** Retrieve the delegate for this cycle *)
val delegation_auction_delegate : delegation_auction -> Ligo.key_hash option

val delegation_auction_cycle : delegation_auction -> Ligo.nat

val delegation_auction_winning_amount : delegation_auction -> Ligo.tez option

(* TODO: can we bid to nominate someone else as a baker? *)
val delegation_auction_place_bid : delegation_auction -> Ligo.address -> Ligo.tez -> delegation_auction_bid Ligo.ticket * delegation_auction

val delegation_auction_claim_win : delegation_auction -> delegation_auction_bid Ligo.ticket -> Ligo.key_hash -> delegation_auction

val delegation_auction_reclaim_bid : delegation_auction -> delegation_auction_bid Ligo.ticket -> Ligo.tez * delegation_auction

val show_delegation_auction : delegation_auction -> string
val pp_delegation_auction : Format.formatter -> delegation_auction -> unit
