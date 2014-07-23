
(*
copyright (c) 2013-2014, simon cruanes
all rights reserved.

redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.  redistributions in binary
form must reproduce the above copyright notice, this list of conditions and the
following disclaimer in the documentation and/or other materials provided with
the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)

(** {1 IO Monad}

A simple abstraction over blocking IO, with strict evaluation. This is in
no way an alternative to Lwt/Async if you need concurrency.

@since NEXT_RELEASE *)

type 'a t
type 'a io = 'a t

type 'a or_error = [ `Ok of 'a | `Error of string ]

val (>>=) : 'a t -> ('a -> 'b t) -> 'b t
(** wait for the result of an action, then use a function to build a
    new action and execute it *)

val return : 'a -> 'a t
(** Just return a value *)

val repeat : int -> 'a t -> 'a list t
(** Repeat an IO action as many times as required *)

val repeat' : int -> 'a t -> unit t
(** Same as {!repeat}, but ignores the result *)

val map : ('a -> 'b) -> 'a t -> 'b t
(** Map values *)

val (>|=) : 'a t -> ('a -> 'b) -> 'b t

val bind : ?finalize:(unit t) -> ('a -> 'b t) -> 'a t -> 'b t
(** [bind f a] runs the action [a] and applies [f] to its result
    to obtain a new action. It then behaves exactly like this new
    action.
    @param finalize an optional action that is always run after evaluating
      the whole action *)

val pure : 'a -> 'a t
val (<*>) : ('a -> 'b) t -> 'a t -> 'b t

val lift : ('a -> 'b) -> 'a t -> 'b t
(** Synonym to {!map} *)

val lift2 : ('a -> 'b -> 'c) -> 'a t -> 'b t -> 'c t
val lift3 : ('a -> 'b -> 'c -> 'd) -> 'a t -> 'b t -> 'c t -> 'd t

val sequence : 'a t list -> 'a list t
(** Runs operations one by one and gather their results *)

val sequence_map : ('a -> 'b t) -> 'a list -> 'b list t
(** Generalization of {!sequence} *)

val fail : string -> 'a t
(** [fail msg] fails with the given message. Running the IO value will
    return an [`Error] variant *)

val run : 'a t -> 'a or_error
(** Run an IO action.
    @return either [`Ok x] when [x] is the successful result of the
      computation, or some [`Error "message"] *)

exception IO_error of string

val run_exn : 'a t -> 'a
(** Unsafe version of {!run}. It assumes non-failure.
    @raise IO_error if the execution didn't go well *)

val register_printer : (exn -> string option) -> unit
(** [register_printer p] register [p] as a possible failure printer.
    If [run a] raises an exception [e], [p e] is evaluated. If [p e = Some msg]
    then the error message will be [msg], otherwise other printers will
    be tried *)

(** {2 Standard Wrappers} *)

(** {6 Input} *)

val with_in : ?flags:open_flag list -> string -> (in_channel -> 'a t) -> 'a t

val read : in_channel -> string -> int -> int -> int t
(** Read a chunk into the given string *)

val read_line : in_channel -> string option t
(** Read a line from the channel. Returns [None] if the input is terminated. *)

val read_lines : in_channel -> string list t
(** Read all lines eagerly *)

val read_all : in_channel -> string t
(** Read the whole channel into a buffer, then converted into a string *)

(** {6 Output} *)

val with_out : ?flags:open_flag list -> string -> (out_channel -> 'a t) -> 'a t

val write : out_channel -> string -> int -> int -> unit t

val write_str : out_channel -> string -> unit t

val write_buf : out_channel -> Buffer.t -> unit t

val write_line : out_channel -> string -> unit t

val flush : out_channel -> unit t

(* TODO: printf/fprintf wrappers *)

(** {2 Streams} *)

module Seq : sig
  type 'a t
  (** An IO stream of values of type 'a, consumable (iterable only once) *)

  val map : ('a -> 'b io) -> 'a t -> 'b t
  (** Map values with actions *)

  val map_pure : ('a -> 'b) -> 'a t -> 'b t
  (** Map values with a pure function *)

  val filter_map : ('a -> 'b option) -> 'a t -> 'b t

  val flat_map : ('a -> 'b t io) -> 'a t -> 'b t
  (** Map each value to a sub sequence of values *)

  val general_iter : ('b -> 'a -> [`Stop | `Continue of ('b * 'c option)] io) ->
                      'b -> 'a t -> 'c t
  (** [general_iter f acc seq] performs a [filter_map] over [seq],
      using [f]. [f] is given a state and the current value, and
      can either return [`Stop] to indicate it stops traversing,
      or [`Continue (st, c)] where [st] is the new state and
      [c] an optional output value.
      The result is the stream of values output by [f] *)

  val tee : ('a -> unit io) list -> 'a t -> 'a t
  (** [tee funs seq] behaves like [seq], but each element is given to
      every function [f] in [funs]. This function [f] returns an action that
      is eagerly executed. *)

  (** {6 Consume} *)

  val iter : ('a -> _ io) -> 'a t -> unit io
  (** Iterate on the stream, with an action for each element *)

  val length : _ t -> int io
  (** Length of the stream *)

  val fold : ('b -> 'a -> 'b io) -> 'b -> 'a t -> 'b io
  (** [fold f acc seq] folds over [seq], consuming it. Every call to [f]
      has the right to return an IO value. *)

  val fold_pure : ('b -> 'a -> 'b) -> 'b -> 'a t -> 'b io
  (** [fold f acc seq] folds over [seq], consuming it. [f] is pure. *)

  (** {6 Standard Wrappers} *)

  type 'a step_result =
    | Yield of 'a
    | Stop

  type 'a gen = unit -> 'a step_result io

  val of_fun : 'a gen -> 'a t
  (** Create a stream from a function that yields an element or stops *)

  val chunks : size:int -> in_channel -> string t
  (** Read the channel's content into chunks of size [size] *)

  val lines : in_channel -> string t
  (** Lines of an input channel *)

  val words : string t -> string t
  (** Split strings into words at " " boundaries *)

  val output : ?sep:string -> out_channel -> string t -> unit io
  (** [output oc seq] outputs every value of [seq] into [oc], separated
      with the optional argument [sep] (default: ["\n"]) *)
end

(** {2 Low level access} *)
module Raw : sig
  val wrap : (unit -> 'a) -> 'a t
  (** [wrap f] is the IO action that, when executed, returns [f ()].
      [f] should be callable as many times as required *)
end
