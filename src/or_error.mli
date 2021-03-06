(** Type for tracking errors in an Error.t. This is a specialization of the Result type,
    where the Error constructor carries an Error.t.

    A common idiom is to wrap a function that is not implemented on all platforms, e.g.:

    val do_something_linux_specific : (unit -> unit) Or_error.t
*)

open Sexplib

(** Serialization and comparison of an [Error] force the error's lazy message. **)
type 'a t = ('a, Error.t) Result.t [@@deriving bin_io, compare, sexp]

(** [Applicative] functions don't have quite the same semantics as
    [Applicative.of_Monad(Or_error)] would give -- [apply (Error e1) (Error e2)] returns
    the combination of [e1] and [e2], whereas it would only return [e1] if it were defined
    using [bind]. *)
include Applicative.S      with type 'a t := 'a t
include Invariant.S1       with type 'a t := 'a t
include Monad.S            with type 'a t := 'a t

val ignore : _ t -> unit t

(** [try_with f] catches exceptions thrown by [f] and returns them in the Result.t as an
    Error.t.  [try_with_join] is like [try_with], except that [f] can throw exceptions or
    return an Error directly, without ending up with a nested error; it is equivalent to
    [Result.join (try_with f)]. *)
val try_with      : ?backtrace:bool (** defaults to [false] *) -> (unit -> 'a  ) -> 'a t
val try_with_join : ?backtrace:bool (** defaults to [false] *) -> (unit -> 'a t) -> 'a t

(** [ok_exn t] throws an exception if [t] is an [Error], and otherwise returns the
    contents of the [Ok] constructor. *)
val ok_exn : 'a t -> 'a

(** [of_exn exn] is [Error (Error.of_exn exn)]. *)
val of_exn : ?backtrace:[ `Get | `This of string ] -> exn -> _ t

(** [of_exn_result (Ok a) = Ok a], [of_exn_result (Error exn) = of_exn exn] *)
val of_exn_result : ('a, exn) Result.t -> 'a t

(** [error] is a wrapper around [Error.create]:

    {[
      error ?strict message a sexp_of_a
      = Error (Error.create ?strict message a sexp_of_a)
    ]}

    As with [Error.create], [sexp_of_a a] is lazily computed, when the info is converted
    to a sexp.  So, if [a] is mutated in the time between the call to [create] and the
    sexp conversion, those mutations will be reflected in the sexp.  Use [~strict:()] to
    force [sexp_of_a a] to be computed immediately. *)
val error
  :  ?strict : unit
  -> string
  -> 'a
  -> ('a -> Sexp.t)
  -> _ t

val error_s : Sexp.t -> _ t

(** [error_string message] is [Error (Error.of_string message)] *)
val error_string : string -> _ t

(** [errorf format arg1 arg2 ...] is [Error (sprintf format arg1 arg2 ...)].  Note that it
    calculates the string eagerly, so when performance matters you may want to use [error]
    instead. *)
val errorf : ('a, unit, string, _ t) format4 -> 'a

(** [tag t string] is [Result.map_error t ~f:(fun e -> Error.tag e string)].
    [tag_arg] is similar. *)
val tag : 'a t -> string -> 'a t
val tag_arg : 'a t -> string -> 'b -> ('b -> Sexp.t) -> 'a t

(** For marking a given value as unimplemented.  Typically combined with conditional
    compilation, where on some platforms the function is defined normally, and on some
    platforms it is defined as unimplemented.  The supplied string should be the name of
    the function that is unimplemented. *)
val unimplemented : string -> _ t

(** [combine_errors ts] returns [Ok] if every element in [ts] is [Ok], else it returns
    [Error] with all the errors in [ts].  More precisely:

    | combine_errors [Ok a1; ...; Ok an] = Ok [a1; ...; an]
    | combine_errors [...; Error e1; ...; Error en; ...]
    |   = Error (Error.of_list [e1; ...; en]) *)
val combine_errors : 'a t list -> 'a list t

(** [combine_errors_unit] returns [Ok] if every element in [ts] is [Ok ()], else it
    returns [Error] with all the errors in [ts], like [combine_errors]. *)
val combine_errors_unit : unit t list -> unit t

module Stable : sig
  (** [Or_error.t] is wire compatible with [V2.t], but not [V1.t], like [Info.Stable]
      and [Error.Stable]. *)
  module V1 : Stable_module_types.S1 with type 'a t = 'a t
  module V2 : Stable_module_types.S1 with type 'a t = 'a t
end
