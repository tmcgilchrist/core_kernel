open Std_internal

let%test_module _ =
  (module (struct

    open Avltree

    type ('k, 'v) t = ('k, 'v) Avltree.t = private
      | Empty
      | Node of ('k, 'v) t * 'k * 'v * int * ('k, 'v) t
      | Leaf of 'k * 'v

    module For_quickcheck = struct

      module Key  = struct include Int    let gen = Quickcheck.Generator.size      end
      module Data = struct include String let gen = String.gen' Char.gen_lowercase end

      let compare = Key.compare

      open Quickcheck
      open Generator

      module Constructor = struct

        type t =
          | Add     of Key.t * Data.t
          | Replace of Key.t * Data.t
          | Remove  of Key.t
        [@@deriving sexp_of]

        let add_gen =
          Key.gen  >>= fun key  ->
          Data.gen >>| fun data ->
          Add (key, data)

        let replace_gen =
          Key.gen  >>= fun key  ->
          Data.gen >>| fun data ->
          Replace (key, data)

        let remove_gen =
          Key.gen >>| fun key ->
          Remove key

        let gen = union [ add_gen ; replace_gen ; remove_gen ]

        let apply_to_tree t tree =
          match t with
          | Add (key, data) ->
            add tree ~key ~data ~compare ~added:(ref false) ~replace:false
          | Replace (key, data) ->
            add tree ~key ~data ~compare ~added:(ref false) ~replace:true
          | Remove key ->
            remove tree key ~compare ~removed:(ref false)

        let apply_to_map t map =
          match t with
          | Add (key, data) ->
            if Map.mem map key
            then map
            else Map.add map ~key ~data
          | Replace (key, data) ->
            Map.add map ~key ~data
          | Remove key ->
            Map.remove map key

      end

      let constructors_gen = List.gen Constructor.gen

      let reify constructors =
        List.fold constructors
          ~init:(empty, Key.Map.empty)
          ~f:(fun (t, map) constructor ->
            Constructor.apply_to_tree constructor t,
            Constructor.apply_to_map  constructor map)

      let merge map1 map2 =
        Map.merge map1 map2 ~f:(fun ~key variant ->
          match variant with
          | `Left data | `Right data -> Some data
          | `Both (data1, data2)     ->
            failwiths "duplicate data for key" (key, data1, data2)
              [%sexp_of: Key.t * Data.t * Data.t])

      let rec to_map = function
        | Empty                            -> Key.Map.empty
        | Leaf (key, data)                 -> Key.Map.singleton key data
        | Node (left, key, data, _, right) ->
          merge (Key.Map.singleton key data)
            (merge (to_map left) (to_map right))

    end

    open For_quickcheck

    let empty = empty

    let%test_unit _ =
      match empty with
      | Empty -> ()
      | _     -> assert false

    let invariant = invariant

    let%test_unit _ =
      Quickcheck.test
        constructors_gen
        ~sexp_of:[%sexp_of: Constructor.t list]
        ~f:(fun constructors ->
          let t, map = reify constructors in
          invariant t ~compare;
          [%test_result: Data.t Key.Map.t] (to_map t) ~expect:map)

    let add = add

    let%test_unit _ =
      Quickcheck.test
        (Quickcheck.Generator.tuple4 constructors_gen Key.gen Data.gen Bool.gen)
        ~sexp_of:[%sexp_of: Constructor.t list * Key.t * Data.t * bool]
        ~f:(fun (constructors, key, data, replace) ->
          let t, map = reify constructors in
          (* test [added], other aspects of [add] are tested via [reify] in the
             [invariant] test above *)
          let added = ref false in
          let _ = add t ~key ~data ~compare ~added ~replace in
          [%test_result: bool]
            !added
            ~expect:(not (Map.mem map key)))

    let remove = remove

    let%test_unit _ =
      Quickcheck.test
        (Quickcheck.Generator.tuple2 constructors_gen Key.gen)
        ~sexp_of:[%sexp_of: Constructor.t list * Key.t]
        ~f:(fun (constructors, key) ->
          let t, map = reify constructors in
          (* test [removed], other aspects of [remove] are tested via [reify] in the
             [invariant] test above *)
          let removed = ref false in
          let _ = remove t key ~compare ~removed in
          [%test_result: bool]
            !removed
            ~expect:(Map.mem map key))

    let find = find

    let%test_unit _ =
      Quickcheck.test
        (Quickcheck.Generator.tuple2 constructors_gen Key.gen)
        ~sexp_of:[%sexp_of: Constructor.t list * Key.t]
        ~f:(fun (constructors, key) ->
          let t, map = reify constructors in
          [%test_result: Data.t option]
            (find t key ~compare)
            ~expect:(Map.find map key))

    let mem = mem

    let%test_unit _ =
      Quickcheck.test
        (Quickcheck.Generator.tuple2 constructors_gen Key.gen)
        ~sexp_of:[%sexp_of: Constructor.t list * Key.t]
        ~f:(fun (constructors, key) ->
          let t, map = reify constructors in
          [%test_result: bool]
            (mem t key ~compare)
            ~expect:(Map.mem map key))

    let first = first

    let%test_unit _ =
      Quickcheck.test
        constructors_gen
        ~sexp_of:[%sexp_of: Constructor.t list]
        ~f:(fun constructors ->
          let t, map = reify constructors in
          [%test_result: (Key.t * Data.t) option]
            (first t)
            ~expect:(Map.min_elt map))

    let last = last

    let%test_unit _ =
      Quickcheck.test
        constructors_gen
        ~sexp_of:[%sexp_of: Constructor.t list]
        ~f:(fun constructors ->
          let t, map = reify constructors in
          [%test_result: (Key.t * Data.t) option]
            (last t)
            ~expect:(Map.max_elt map))

    let find_and_call = find_and_call

    let%test_unit _ =
      Quickcheck.test
        (Quickcheck.Generator.tuple2 constructors_gen Key.gen)
        ~sexp_of:[%sexp_of: Constructor.t list * Key.t]
        ~f:(fun (constructors, key) ->
          let t, map = reify constructors in
          [%test_result: [ `Found of Data.t | `Not_found of Key.t ]]
            (find_and_call t key ~compare
               ~if_found:     (fun data -> `Found     data)
               ~if_not_found: (fun key  -> `Not_found key))
            ~expect:(match Map.find map key with
                     | None      -> `Not_found key
                     | Some data -> `Found     data))

    let iter = iter

    let%test_unit _ =
      Quickcheck.test
        constructors_gen
        ~sexp_of:[%sexp_of: Constructor.t list]
        ~f:(fun constructors ->
          let t, map = reify constructors in
          [%test_result: (Key.t * Data.t) list]
            (let q = Queue.create () in
             iter t ~f:(fun ~key ~data ->
               Queue.enqueue q (key, data));
             Queue.to_list q)
            ~expect:(Map.to_alist map))

    let fold = fold

    let%test_unit _ =
      Quickcheck.test
        constructors_gen
        ~sexp_of:[%sexp_of: Constructor.t list]
        ~f:(fun constructors ->
          let t, map = reify constructors in
          [%test_result: (Key.t * Data.t) list]
            (fold t ~init:[] ~f:(fun ~key ~data acc ->
               (key, data) :: acc))
            ~expect:(Map.to_alist map |> List.rev))

  end : module type of Avltree))
