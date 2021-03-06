(*
 DSub (D<:) with Full Term Dependent Types
 T ::= Top | Bot | t.Type | { Type: S..U } | (z: T) -> T^z
 t ::= x | { Type = T } | lambda x:T.t | t t
*)

Require Export SfLib.

Require Export Arith.EqNat.
Require Export Arith.Le.
Require Import Coq.Program.Equality.

(* ### Syntax ### *)

Definition id := nat.

(* term variables occurring in types *)
Inductive var : Type :=
| varF : id -> var (* free, in concrete environment *)
| varH : id -> var (* free, in abstract environment  *)
| varB : id -> var (* locally-bound variable *)
.

Inductive ty : Type :=
| TTop : ty
| TBot : ty
(* (z: T) -> T^z *)
| TAll : ty -> ty -> ty
(* t.Type *)
| TSel : tm -> ty
(* { Type: S..U } *)
| TMem : ty(*S*) -> ty(*U*) -> ty

with tm : Type :=
(* x -- only free variables, matching concrete environment for terms,
   other cases neede for variables in terms of types
*)
| tvar : var -> tm
(* { Type = T } *)
| ttyp : ty -> tm
(* lambda x:T.t *)
| tabs : ty -> tm -> tm
(* t t *)
| tapp : tm -> tm -> tm
.

Inductive vl : Type :=
(* a closure for a lambda abstraction *)
| vabs : list vl (*H*) -> ty -> tm -> vl
(* a closure for a first-class type *)
| vty : list vl (*H*) -> ty -> vl
.

Definition tenv := list ty. (* Gamma environment: static *)
Definition venv := list vl. (* H environment: run-time *)
Definition aenv := list (venv*ty). (* J environment: abstract at run-time *)

(* ### Representation of Bindings ### *)

(* An environment is a list of values, indexed by decrementing ids. *)

Fixpoint index {X : Type} (n : id) (l : list X) : option X :=
  match l with
    | [] => None
    | a :: l' =>
      if (beq_nat n (length l')) then Some a else index n l'
  end.

Inductive var_closed: nat(*B*) -> nat(*H*) -> nat(*F*) -> var -> Prop :=
| clv_f: forall i j k x,
    k > x ->
    var_closed i j k (varF x)
| clv_h: forall i j k x,
    j > x ->
    var_closed i j k (varH x)
| clv_b: forall i j k x,
    i > x ->
    var_closed i j k (varB x)
.
Inductive closed: nat(*B*) -> nat(*H*) -> nat(*F*) -> ty -> Prop :=
| cl_top: forall i j k,
    closed i j k TTop
| cl_bot: forall i j k,
    closed i j k TBot
| cl_all: forall i j k T1 T2,
    closed i j k T1 ->
    closed (S i) j k T2 ->
    closed i j k (TAll T1 T2)
| cl_sel: forall i j k t,
    tm_closed i j k t ->
    closed i j k (TSel t)
| cl_mem: forall i j k T1 T2,
    closed i j k T1 ->
    closed i j k T2 ->
    closed i j k (TMem T1 T2)
with tm_closed: nat(*B*) -> nat(*H*) -> nat(*F*) -> tm -> Prop :=
| clt_var: forall i j k v,
    var_closed i j k v ->
    tm_closed i j k (tvar v)
| clt_typ: forall i j k T,
    closed i j k T ->
    tm_closed i j k (ttyp T)
| clt_abs: forall i j k T t,
    closed i j k T ->
    tm_closed i j (S k) t ->
    tm_closed i j k (tabs T t)
| clt_app: forall i j k t1 t2,
    tm_closed i j k t1 ->
    tm_closed i j k t2 ->
    tm_closed i j k (tapp t1 t2)
.

(* open define a locally-nameless encoding wrt to TVarB type variables. *)
(* substitute term u for all occurrences of (tvar (varB k)) *)
Fixpoint open_rec (k: nat) (u: tm) (T: ty) { struct T }: ty :=
  match T with
    | TTop        => TTop
    | TBot        => TBot
    | TAll T1 T2  => TAll (open_rec k u T1) (open_rec (S k) u T2)
    | TSel t      => TSel (tm_open_rec k u t)
    | TMem T1 T2  => TMem (open_rec k u T1) (open_rec k u T2)
  end
with tm_open_rec (k: nat) (u: tm) (t: tm) { struct t }: tm :=
   match t with
    | tvar (varB i) => if beq_nat k i then u else (tvar (varB i))
    | tvar v      => tvar v
    | ttyp T      => ttyp (open_rec k u T)
    | tabs T t    => tabs (open_rec k u T) (tm_open_rec k u t)
    | tapp t1 t2  => tapp (tm_open_rec k u t1) (tm_open_rec k u t2)
  end.

Definition open u T := open_rec 0 u T.

(* Locally-nameless encoding with respect to varH variables. *)
Fixpoint subst (U : tm) (T : ty) {struct T} : ty :=
  match T with
    | TTop         => TTop
    | TBot         => TBot
    | TAll T1 T2   => TAll (subst U T1) (subst U T2)
    | TSel t       => TSel (tm_subst U t)
    | TMem T1 T2   => TMem (subst U T1) (subst U T2)
  end
with tm_subst (U : tm) (t : tm) {struct t} : tm :=
  match t with
    | tvar (varH i) => if beq_nat i 0 then U else tvar (varH (i-1))
    | tvar v      => tvar v
    | ttyp T      => ttyp (subst U T)
    | tabs T t    => tabs (subst U T) (tm_subst U t)
    | tapp t1 t2  => tapp (tm_subst U t1) (tm_subst U t2)
  end.

Fixpoint nosubst (T : ty) {struct T} : Prop :=
  match T with
    | TTop         => True
    | TBot         => True
    | TAll T1 T2   => nosubst T1 /\ nosubst T2
    | TSel t       => tm_nosubst t
    | TMem T1 T2   => nosubst T1 /\ nosubst T2
  end
with tm_nosubst (t : tm) {struct t} : Prop :=
  match t with
    | tvar (varH i) => i <> 0
    | tvar v      => True
    | ttyp T      => nosubst T
    | tabs T t    => nosubst T /\ tm_nosubst t
    | tapp t1 t2  => tm_nosubst t1 /\ tm_nosubst t2
  end.

(* ### Static Subtyping ### *)
(*
The first env is for looking up varF variables.
The first env matches the concrete runtime environment, and is
extended during type assignment.

The second env is for looking up varH variables.
The second env matches the abstract runtime environment, and is
extended during subtyping.
*)
Inductive stp: tenv -> tenv -> ty -> ty -> Prop :=
| stp_top: forall G1 GH T1,
    closed 0 (length GH) (length G1) T1 ->
    stp G1 GH T1 TTop
| stp_bot: forall G1 GH T2,
    closed 0 (length GH) (length G1) T2 ->
    stp G1 GH TBot T2
| stp_mem: forall G1 GH S1 U1 S2 U2,
    stp G1 GH U1 U2 ->
    stp G1 GH S2 S1 ->
    stp G1 GH (TMem S1 U1) (TMem S2 U2)
| stp_sel1: forall G1 GH TX T2 t,
    has_type G1 GH t TX ->
    stp G1 GH TX (TMem TBot T2) ->
    stp G1 GH (TSel t) T2
| stp_sel2: forall G1 GH TX T1 t,
    has_type G1 GH t TX ->
    stp G1 GH TX (TMem T1 TTop) ->
    stp G1 GH T1 (TSel t)
(* TODO: generalize abstract selection to full terms *)
| stp_sela1: forall G1 GH TX T2 x,
    index x GH = Some TX ->
    closed 0 x (length G1) TX ->
    stp G1 GH TX (TMem TBot T2) ->
    stp G1 GH (TSel (tvar (varH x))) T2
| stp_sela2: forall G1 GH TX T1 x,
    index x GH = Some TX ->
    closed 0 x (length G1) TX ->
    stp G1 GH TX (TMem T1 TTop) ->
    stp G1 GH T1 (TSel (tvar (varH x)))
| stp_selx: forall G1 GH t,
    tm_closed 0 (length GH) (length G1) t ->
    stp G1 GH (TSel t) (TSel t)
| stp_all: forall G1 GH T1 T2 T3 T4 x,
    stp G1 GH T3 T1 ->
    x = length GH ->
    closed 1 (length GH) (length G1) T2 ->
    closed 1 (length GH) (length G1) T4 ->
    stp G1 (T3::GH) (open (tvar (varH x)) T2) (open (tvar (varH x)) T4) ->
    stp G1 GH (TAll T1 T2) (TAll T3 T4)

(* ### Type Assignment ### *)
with has_type : tenv -> tenv -> tm -> ty -> Prop :=
| t_varF: forall x G1 GH T1,
           index x G1 = Some T1 ->
           closed 0 0 (length G1) T1 ->
           has_type G1 GH (tvar (varF x)) T1
(* TODO
| t_varH: forall x G1 GH T1,
           index x GH = Some T1 ->
           closed 0 x (length G1) T1 ->
           has_type G1 GH (tvar (varH x)) T1
*)
| t_typ: forall G1 GH T1,
           closed 0 (length GH) (length G1) T1 ->
           has_type G1 GH (ttyp T1) (TMem T1 T1)
| t_app: forall G1 GH f x T1 T2 T,
           has_type G1 GH f (TAll T1 T2) ->
           has_type G1 GH x T1 ->
           T = open x T2 ->
           closed 0 (length GH) (length G1) T ->
           has_type G1 GH (tapp f x) T
| t_abs: forall G1 GH y T1 T2,
           has_type (T1::G1) GH y (open (tvar (varF (length G1))) T2) ->
           closed 0 0 (length G1) T1 -> (* for splicing... TODO: revisit what is necessary, re: other closed 0 0 restrictions *)
           closed 0 (length GH) (length G1) (TAll T1 T2) ->
           has_type G1 GH (tabs T1 y) (TAll T1 T2)
| t_sub: forall G1 GH e T1 T2,
           has_type G1 GH e T1 ->
           stp G1 GH T1 T2 ->
           has_type G1 GH e T2
.

(* ### Evaluation (Big-Step Semantics) ### *)

(*
None             means timeout
Some None        means stuck
Some (Some v))   means result v

Could use do-notation to clean up syntax.
*)

Fixpoint teval(n: nat)(env: venv)(t: tm){struct n}: option (option vl) :=
  match n with
    | 0 => None
    | S n =>
      match t with
        | tvar (varF x) => Some (index x env)
        | tvar (varH _) => None
        | tvar (varB _) => None
        | ttyp T => Some (Some (vty env T))
        | tabs T y => Some (Some (vabs env T y))
        | tapp ef ex   =>
          match teval n env ex with
            | None => None
            | Some None => Some None
            | Some (Some vx) =>
              match teval n env ef with
                | None => None
                | Some None => Some None
                | Some (Some (vty _ _)) => Some None
                | Some (Some (vabs env2 _ ey)) =>
                  teval n (vx::env2) ey
              end
          end
      end
  end.

Definition base (v:vl): venv :=
  match v with
    | vty GX _ => GX
    | vabs GX _ _ => GX
  end.

(*
 For evaluation of terms in types,
 we need to ensure that closures are comparable regardless of environment extension.
 So we cutoff the environment consistently, based on the free variables in the term.
 *)
Fixpoint var_req_env (v: var): nat :=
  match v with
    | varF n => 1 + n
    | _ => 0
  end.
Fixpoint tm_req_env (t:tm): nat :=
  match t with
    | tvar (varF n) => 1 + n
    | tvar _ => 0
    | ttyp T => ty_req_env T
    | tabs T t0 => max (ty_req_env T) (tm_req_env t0)
    | tapp t1 t2 => max (tm_req_env t1) (tm_req_env t2)
  end
with ty_req_env (T:ty): nat :=
  match T with
    | TTop => 0
    | TBot => 0
    | TAll T1 T2 => max (ty_req_env T1) (ty_req_env T2)
    | TSel t => tm_req_env t
    | TMem T1 T2 => max (ty_req_env T1) (ty_req_env T2)
  end.

Fixpoint tail {X : Type} (n : nat) (l : list X) : list X :=
  match l with
    | [] => []
    | _::l' => if (beq_nat n (length l)) then l else tail n l'
  end.

Definition peval (G1: venv) (t: tm) v :=
  tm_closed 0 0 (length G1) t /\
  tm_req_env t <= length G1 /\
  exists n, teval n (tail (tm_req_env t) G1) t = Some (Some v).

Definition join_env {X:Type} (l1: list X) (l2: list X) (l: list X) :=
  exists l1' l2', l1=l1'++l /\ l2=l2'++l.

(* ### Runtime Subtyping ### *)
(* H1 T1 <: H2 T2 -| J *)
Inductive stp2: bool (* whether selections are precise *) ->
                bool (* whether the last rule may not be transitivity *) ->
                venv -> ty -> venv -> ty -> aenv  ->
                nat (* derivation size *) ->
                Prop :=
| stp2_top: forall G1 G2 GH T s n,
    closed 0 (length GH) (length G1) T ->
    stp2 s true G1 T G2 TTop GH (S n)
| stp2_bot: forall G1 G2 GH T s n,
    closed 0 (length GH) (length G2) T ->
    stp2 s true G1 TBot G2 T GH (S n)
| stp2_mem: forall G1 G2 S1 U1 S2 U2 GH s n1 n2,
    stp2 s s G1 U1 G2 U2 GH n1 ->
    stp2 s false G2 S2 G1 S1 GH n2 ->
    stp2 s true G1 (TMem S1 U1) G2 (TMem S2 U2) GH (S (n1+n2))

(* concrete type variables *)
(* precise/invertible bounds *)
(* vty already marks binding as type binding, so no need for additional TMem marker *)
| stp2_strong_sel1: forall G1 G2 GX TX t T2 GH n1,
    peval G1 t (vty GX TX) ->
    val_type GX (vty GX TX) (TMem TX TX) -> (* for downgrade *)
    closed 0 0 (length GX) TX ->
    stp2 true true GX TX G2 T2 GH n1 ->
    stp2 true true G1 (TSel t) G2 T2 GH (S n1)
| stp2_strong_sel2: forall G1 G2 GX TX t T1 GH n1,
    peval G2 t (vty GX TX) ->
    val_type GX (vty GX TX) (TMem TX TX) -> (* for downgrade *)
    closed 0 0 (length GX) TX ->
    stp2 true false G1 T1 GX TX GH n1 ->
    stp2 true true G1 T1 G2 (TSel t) GH (S n1)
(* imprecise type *)
| stp2_sel1: forall G1 G2 v TX t T2 GH n1,
    peval G1 t v ->
    val_type (base v) v TX ->
    closed 0 0 (length (base v)) TX ->
    stp2 false false (base v) TX G2 (TMem TBot T2) GH n1 ->
    stp2 false true G1 (TSel t) G2 T2 GH (S n1)
| stp2_sel2: forall G1 G2 v TX t T1 GH n1,
    peval G2 t v ->
    val_type (base v) v TX ->
    closed 0 0 (length (base v)) TX ->
    stp2 false false (base v) TX G1 (TMem T1 TTop) GH n1 ->
    stp2 false true G1 T1 G2 (TSel t) GH (S n1)
| stp2_selxr: forall G1 G2 G t GH s n,
    join_env G1 G2 G ->
    tm_closed 0 (length GH) (length G) t ->
    stp2 s true G1 (TSel t) G2 (TSel t) GH (S n)
| stp2_selx: forall G1 G2 v t1 t2 GH s n,
    peval G1 t1 v ->
    peval G2 t2 v ->
    stp2 s true G1 (TSel t1) G2 (TSel t2) GH (S n)

(* abstract type variables *)
| stp2_sela1: forall G1 G2 GX TX x T2 GH n1,
    index x GH = Some (GX, TX) ->
    closed 0 x (length GX) TX ->
    stp2 false false GX TX G2 (TMem TBot T2) GH n1 ->
    stp2 false true G1 (TSel (tvar (varH x))) G2 T2 GH (S n1)
| stp2_sela2: forall G1 G2 GX T1 TX x GH n1,
    index x GH = Some (GX, TX) ->
    closed 0 x (length GX) TX ->
    stp2 false false GX TX G1 (TMem T1 TTop) GH n1 ->
    stp2 false true G1 T1 G2 (TSel (tvar (varH x))) GH (S n1)
(* covered by selxr
| stp2_selax: forall G1 G2 v x GH s n,
    index x GH = Some v ->
    stp2 s true G1 (TSel (tvar (varH x))) G2 (TSel (tvar (varH x))) GH (S n)
*)

| stp2_all: forall G1 G2 T1 T2 T3 T4 x GH s n1 n2,
    stp2 false false G2 T3 G1 T1 GH n1 ->
    x = length GH ->
    closed 1 (length GH) (length G1) T2 ->
    closed 1 (length GH) (length G2) T4 ->
    stp2 false false G1 (open (tvar (varH x)) T2) G2 (open (tvar (varH x)) T4) ((G2, T3)::GH) n2 ->
    stp2 s true G1 (TAll T1 T2) G2 (TAll T3 T4) GH (S (n1 + n2))

| stp2_wrapf: forall G1 G2 T1 T2 GH s n1,
    stp2 s true G1 T1 G2 T2 GH n1 ->
    stp2 s false G1 T1 G2 T2 GH (S n1)

| stp2_transf: forall G1 G2 G3 T1 T2 T3 GH s n1 n2,
    stp2 s true G1 T1 G2 T2 GH n1 ->
    stp2 s false G2 T2 G3 T3 GH n2 ->
    stp2 s false G1 T1 G3 T3 GH (S (n1+n2))

(* consistent environment *)
with wf_env : venv -> tenv -> Prop :=
| wfe_nil : wf_env nil nil
| wfe_cons : forall v t vs ts,
    val_type (v::vs) v t ->
    wf_env vs ts ->
    wf_env (cons v vs) (cons t ts)

(* value type assignment *)
with val_type : venv -> vl -> ty -> Prop :=
| v_ty: forall env venv tenv T1 TE,
    wf_env venv tenv ->
    (exists n, stp2 true true venv (TMem T1 T1) env TE [] n) ->
    val_type env (vty venv T1) TE
| v_abs: forall env venv tenv x y T1 T2 TE,
    wf_env venv tenv ->
    has_type (T1::tenv) [] y (open (tvar (varF x)) T2) ->
    length venv = x ->
    (exists n, stp2 true true venv (TAll T1 T2) env TE [] n) ->
    val_type env (vabs venv T1 y) TE
.

Inductive wf_envh : venv -> aenv -> tenv -> Prop :=
| wfeh_nil : forall vvs, wf_envh vvs nil nil
| wfeh_cons : forall t vs vvs ts,
    wf_envh vvs vs ts ->
    wf_envh vvs (cons (vvs,t) vs) (cons t ts)
.

Inductive valh_type : venv -> aenv -> (venv*ty) -> ty -> Prop :=
| v_tya: forall aenv venv T1,
    valh_type venv aenv (venv, T1) T1
.

(* automation *)
Hint Unfold venv.
Hint Unfold tenv.

Hint Unfold open.
Hint Unfold index.
Hint Unfold length.

Hint Constructors ty.
Hint Constructors tm.
Hint Constructors vl.

Hint Constructors closed tm_closed var_closed.
Hint Constructors has_type.
Hint Constructors val_type.
Hint Constructors wf_env.
Hint Constructors wf_envh.
Hint Constructors stp.
Hint Constructors stp2.

Hint Constructors option.
Hint Constructors list.

Hint Resolve ex_intro.

(* ############################################################ *)
(* Examples *)
(* ############################################################ *)

Ltac crush :=
  try solve [eapply stp_selx; compute; eauto; crush];
  try solve [econstructor; compute; eauto; crush];
  try solve [eapply t_sub; crush].

(* define polymorphic identity function *)

Definition polyId := TAll (TMem TBot TTop) (TAll (TSel (tvar (varB 0))) (TSel (tvar (varB 1)))).

Example ex1: has_type [] [] (tabs (TMem TBot TTop) (tabs (TSel (tvar (varF 0))) (tvar (varF 1)))) polyId.
Proof.
  crush.
Qed.

(* instantiate it to TTop *)
Example ex2: has_type [polyId] [] (tapp (tvar (varF 0)) (ttyp TTop)) (TAll TTop TTop).
Proof.
  (* TODO: not sure why crush doesn't solve this directly. *)
  eapply t_sub. eapply t_app; crush. crush.
Qed.

Example ex3: has_type [] [] (tabs (TAll TTop (TMem TBot TTop)) (tabs (TSel (tapp (tvar (varF 0)) (tvar (varF 0)))) (tvar (varF 1))))
  (TAll (TAll TTop (TMem TBot TTop)) (TAll (TSel (tapp (tvar (varB 0)) (tvar (varB 0)))) (TSel (tapp (tvar (varB 1)) (tvar (varB 1)))))).
Proof.
  crush.
Qed.

(* type Rep[T], abstract *)
Definition _repT := (TAll (TMem TBot TTop) (TMem TBot TTop)).
(* type Rep[T] = T *)
Definition _repTeqT := (TAll (TMem TBot TTop) (TMem (TSel (tvar (varB 0))) (TSel (tvar (varB 0))))).
(* type Rep[T] = TTop *)
Definition _repTeqTop := (TAll (TMem TBot TTop) (TMem TTop TTop)).
(* type Rep[T] = T -> T, partially revealed *)
Definition _repTeqTfun := (TAll (TMem TBot TTop) (TMem TBot (TAll (TSel (tvar (varB 0))) (TSel (tvar (varB 1)))))).
Example _sub_repTeqT: stp [] [] _repTeqT _repT.
Proof.
  eapply stp_all; crush.
Qed.
Example _sub_repTeqTop: stp [] [] _repTeqTop _repT.
Proof.
  eapply stp_all; crush.
Qed.
Example _sub_repTeqTfun: stp [] [] _repTeqTfun _repT.
Proof.
  eapply stp_all; crush.
Qed.

(* type-check the rep implementations *)
Definition _implRepTeq T := tabs (TMem TBot TTop) (ttyp T).
Example _typ_repTeqT: has_type [] [] (_implRepTeq (TSel (tvar (varF 0)))) _repTeqT.
Proof.
  eapply t_abs; crush.
Qed.
Example _typ_repTeqTop: has_type [] [] (_implRepTeq TTop) _repTeqTop.
Proof.
  eapply t_abs; crush.
Qed.
Example _typ_repTeqTfun: has_type [] [] (_implRepTeq (TAll (TSel (tvar (varF 0))) (TSel (tvar (varF 0))))) _repTeqTfun.
Proof.
  eapply t_abs; crush.
Qed.

(* apply Rep as a type *)
Example _app_repT_warmup: stp [_repT] [] (TSel (tapp (tvar (varF 0)) (ttyp TTop))) TTop.
Proof.
  eapply stp_top. crush.
Qed.
Example _app_repTeqT: stp [_repTeqT] [] TTop (TSel (tapp (tvar (varF 0)) (ttyp TTop))).
Proof.
  eapply stp_sel2. eapply t_app; crush. crush.
Qed.
Example _app_repTeqTop: has_type [_repTeqTop] [] (tabs (TMem TBot TTop) (tabs (TSel (tapp (tvar (varF 0)) (tvar (varF 1)))) (tvar (varF 2)))) (TAll (TMem TBot TTop) (TAll TTop TTop)).
Proof.
  eapply t_abs. simpl. eapply t_sub. eapply t_abs with (T2:=TTop); crush.
  unfold open. simpl. eapply stp_all; crush. eapply stp_sel2; crush. crush. crush.
Qed.
Example _app_repT: has_type [_repT] [] (tabs (TMem TBot TTop) (tabs (TSel (tapp (tvar (varF 0)) (tvar (varF 1)))) (tvar (varF 2)))) (TAll (TMem TBot TTop) (TAll (TSel (tapp (tvar (varF 0)) (tvar (varB 0)))) (TSel (tapp (tvar (varF 0)) (tvar (varB 1)))))).
Proof.
  eapply t_abs; crush.
Qed.
Example _app_repT_abs: has_type [] [] (tabs _repT (tabs (TMem TBot TTop) (tabs (TSel (tapp (tvar (varF 0)) (tvar (varF 1)))) (tvar (varF 2))))) (TAll _repT (TAll (TMem TBot TTop) (TAll (TSel (tapp (tvar (varB 1)) (tvar (varB 0)))) (TSel (tapp (tvar (varB 2)) (tvar (varB 1))))))).
Proof.
  eapply t_abs; crush.
Qed.

Example ex4_warmup:
  stp [] []
      (TAll _repT (TAll (TMem TBot TTop) (TAll (TSel (tapp (tvar (varB 1)) (tvar (varB 0)))) (TSel (tapp (tvar (varB 2)) (tvar (varB 1)))))))
      (TAll _repT (TAll (TMem TBot TTop) (TAll (TSel (tapp (tvar (varB 1)) (tvar (varB 0)))) (TSel (tapp (tvar (varB 2)) (tvar (varB 1))))))).
Proof.
  eapply stp_all; crush.
Qed.

Example ex4:
  stp [] []
      (TAll _repT (TAll (TMem TBot TTop) (TAll (TSel (tapp (tvar (varB 1)) (tvar (varB 0)))) (TSel (tapp (tvar (varB 2)) (tvar (varB 1)))))))
      (TAll _repTeqT (TAll (TMem TBot TTop) (TAll (TSel (tapp (tvar (varB 1)) (tvar (varB 0)))) (TSel (tapp (tvar (varB 2)) (tvar (varB 1))))))).
Proof.
  eapply stp_all; crush.
Qed.

Example ex5_warmup:
  stp [] []
      (TAll (TMem TBot TTop) (TSel (tapp (tabs TTop (ttyp TTop)) (ttyp TBot))))
      (TAll (TMem TBot TTop) TTop).
Proof.
  eapply stp_all; crush.
Qed.

Example ex5:
  stp [] []
      (TAll (TMem TBot TTop) TTop)
      (TAll (TMem TBot TTop) (TSel (tapp (tabs TTop (ttyp TTop)) (ttyp TBot)))).
Proof.
  eapply stp_all. crush. simpl. reflexivity. simpl. eauto. simpl.
  econstructor; crush.
  unfold open. simpl.
  eapply stp_sel2.
  eapply t_app. eapply t_abs with (T2:=TMem TTop TTop); crush. crush.
  unfold open. simpl. reflexivity. crush. crush.
Qed.

Example ex6_warmup:
  stp [] []
      (TAll (TMem TBot TTop) (TSel (tapp (tabs (TMem TBot TTop) (ttyp TTop)) (ttyp (TSel (tvar (varB 0)))))))
      (TAll (TMem TBot TTop) TTop).
Proof.
  eapply stp_all; crush.
Qed.

Example ex6:
  stp [] []
      (TAll (TMem TBot TTop) TTop)
      (TAll (TMem TBot TTop) (TSel (tapp (tabs (TMem TBot TTop) (ttyp TTop)) (ttyp (TSel (tvar (varB 0))))))).
Proof.
  eapply stp_all. crush. simpl. reflexivity. simpl. eauto. simpl.
  econstructor; crush.
  unfold open. simpl.
  eapply stp_sel2.
  eapply t_app. eapply t_abs with (T2:=TMem TTop TTop); crush.
  eapply t_sub. crush. crush.
  unfold open. simpl. reflexivity. crush. crush.
Qed.

Example ex7_warmup:
  stp [] []
      (TAll (TMem TBot TTop) (TSel (tapp (tabs (TMem TBot (TSel (tvar (varB 0)))) (ttyp TTop)) (ttyp (TSel (tvar (varB 0)))))))
      (TAll (TMem TBot TTop) TTop).
Proof.
  eapply stp_all; crush.
Qed.

(*
Example ex7:
  stp [] []
      (TAll (TMem TBot TTop) TTop)
      (TAll (TMem TBot TTop) (TSel (tapp (tabs (TMem TBot (TSel (tvar (varB 0)))) (ttyp TTop)) (ttyp (TSel (tvar (varB 0))))))).
Proof.
  eapply stp_all. crush. simpl. reflexivity. simpl. eauto. simpl.
  econstructor; crush.
  unfold open. simpl.
  eapply stp_sel2.
  eapply t_app. eapply t_abs with (T2:=TMem TTop TTop); crush.
  (* fails because of closed 0 0 0 (TMem TBot (TSel (tvar (varH 0)))) *)
*)

Example ex7_closure_conversion_tp:
  has_type [] [] (tabs (TMem TBot TTop) (tabs (TMem TBot (TSel (tvar (varF 0)))) (ttyp TTop)))
           (TAll (TMem TBot TTop) (TAll (TMem TBot (TSel (tvar (varB 0)))) (TMem TTop TTop))).
Proof.
  eapply t_abs; crush.
Qed.

(* TODO: enable once abstract type selection generalized to full terms
Example ex7_closure_conversion_sub:
  stp [(TAll (TMem TBot TTop) (TAll (TMem TBot (TSel (tvar (varB 0)))) (TMem TTop TTop)))] []
      (TAll (TMem TBot TTop) TTop)
      (TAll (TMem TBot TTop) (TSel (tapp (tapp (tvar (varF 0)) (tvar (varB 0))) (ttyp (TSel (tvar (varB 0))))))).
Proof.
  eapply stp_all. crush. simpl. reflexivity. simpl. eauto. simpl.
  econstructor; crush.
  unfold open. simpl.
  eapply stp_sel2.
  eapply t_app. eapply t_app. eapply t_varF; crush. eapply t_varH; crush.
  unfold open. simpl. reflexivity. simpl. crush.
  eapply t_sub. eapply t_typ; crush. eapply stp_mem. crush. crush.
  unfold open. simpl. reflexivity. crush. crush.
Qed.
*)

(* ############################################################ *)
(* Proofs *)
(* ############################################################ *)

Ltac ev := repeat match goal with
                    | H: exists _, _ |- _ => destruct H
                    | H: _ /\  _ |- _ => destruct H
           end.

Fixpoint tsize (T: ty) :=
  match T with
    | TTop => 1
    | TBot => 1
    | TAll T1 T2 => S (tsize T1 + tsize T2)
    | TSel t => tm_tsize t
    | TMem T1 T2 => S (tsize T1 + tsize T2)
  end
with tm_tsize (t: tm) :=
   match t with
    | tvar _ => 1
    | ttyp T      => S (tsize T)
    | tabs T t    => S (tsize T + tm_tsize t)
    | tapp t1 t2  => S (tm_tsize t1 + tm_tsize t2)
  end.

Scheme ty_mut := Induction for ty Sort Prop
with   tm_mut := Induction for tm Sort Prop.
Combined Scheme tytm_mutind from ty_mut, tm_mut.

Lemma open_preserves_size:
  (forall T x j, tsize T = tsize (open_rec j (tvar (varH x)) T)) /\
  (forall t x j, tm_tsize t = tm_tsize (tm_open_rec j (tvar (varH x)) t)).
Proof.
  apply tytm_mutind; intros; simpl; eauto.
  destruct v; simpl; destruct (beq_nat j i); eauto.
Qed.

(* ## Extension, Regularity ## *)

Lemma wf_length : forall vs ts,
                    wf_env vs ts ->
                    (length vs = length ts).
Proof.
  intros. induction H. auto.
  compute. eauto.
Qed.

Hint Immediate wf_length.

Lemma wfh_length : forall vvs vs ts,
                    wf_envh vvs vs ts ->
                    (length vs = length ts).
Proof.
  intros. induction H. auto.
  compute. eauto.
Qed.

Hint Immediate wfh_length.

Lemma index_max : forall X vs n (T: X),
                       index n vs = Some T ->
                       n < length vs.
Proof.
  intros X vs. induction vs.
  - Case "nil". intros. inversion H.
  - Case "cons".
    intros. inversion H.
    case_eq (beq_nat n (length vs)); intros E2.
    + SSCase "hit".
      eapply beq_nat_true in E2. subst n. compute. eauto.
    + SSCase "miss".
      rewrite E2 in H1.
      assert (n < length vs). eapply IHvs. apply H1.
      compute. eauto.
Qed.

Lemma le_xx : forall a b,
                       a <= b ->
                       exists E, le_lt_dec a b = left E.
Proof. intros.
  case_eq (le_lt_dec a b). intros. eauto.
  intros. omega.
Qed.
Lemma le_yy : forall a b,
                       a > b ->
                       exists E, le_lt_dec a b = right E.
Proof. intros.
  case_eq (le_lt_dec a b). intros. omega.
  intros. eauto.
Qed.

Lemma index_extend : forall X vs n x (T: X),
                       index n vs = Some T ->
                       index n (x::vs) = Some T.

Proof.
  intros.
  assert (n < length vs). eapply index_max. eauto.
  assert (beq_nat n (length vs) = false) as E. eapply beq_nat_false_iff. omega.
  unfold index. unfold index in H. rewrite H. rewrite E. reflexivity.
Qed.

Lemma var_closed_inc_mult:
  (forall v i j k,
   var_closed i j k v ->
   forall i' j' k',
   i' >= i -> j' >= j -> k' >= k ->
   var_closed i' j' k' v).
Proof.
  intros. inversion H; subst; constructor; omega.
Qed.

Lemma closed_inc_mult:
  (forall T i j k,
   closed i j k T ->
   forall i' j' k',
   i' >= i -> j' >= j -> k' >= k ->
   closed i' j' k' T) /\
  (forall t i j k,
   tm_closed i j k t ->
   forall i' j' k',
   i' >= i -> j' >= j -> k' >= k ->
   tm_closed i' j' k' t).
Proof.
  apply tytm_mutind; intros; eauto;
  try solve [inversion H1; subst; econstructor; eauto; eapply H0; eauto; omega];
  try solve [inversion H0; subst; econstructor; eauto; eapply H0; eauto; omega].
  inversion H; subst. econstructor. eapply var_closed_inc_mult; eauto.
Qed.

Lemma closed_inc: forall i j k T,
  closed i j k T ->
  closed i (S j) k T.
Proof.
  intros. apply ((proj1 closed_inc_mult) T i j k H i (S j) k); omega.
Qed.

Lemma tm_closed_inc: forall i j k t,
  tm_closed i j k t ->
  tm_closed i (S j) k t.
Proof.
  intros. apply ((proj2 closed_inc_mult) t i j k H i (S j) k); omega.
Qed.

Lemma closed_upgrade: forall i j k i' T,
 closed i j k T ->
 i' >= i ->
 closed i' j k T.
Proof.
 intros. apply ((proj1 closed_inc_mult) T i j k H i' j k); omega.
Qed.

Lemma tm_closed_upgrade: forall i j k i' t,
 tm_closed i j k t ->
 i' >= i ->
 tm_closed i' j k t.
Proof.
 intros. apply ((proj2 closed_inc_mult) t i j k H i' j k); omega.
Qed.

Lemma closed_upgrade_free: forall i j k j' T,
 closed i j k T ->
 j' >= j ->
 closed i j' k T.
Proof.
 intros. apply ((proj1 closed_inc_mult) T i j k H i j' k); omega.
Qed.

Lemma tm_closed_upgrade_free: forall i j k j' t,
 tm_closed i j k t ->
 j' >= j ->
 tm_closed i j' k t.
Proof.
 intros. apply ((proj2 closed_inc_mult) t i j k H i j' k); omega.
Qed.

Lemma closed_upgrade_freef: forall i j k k' T,
 closed i j k T ->
 k' >= k ->
 closed i j k' T.
Proof.
 intros. apply ((proj1 closed_inc_mult) T i j k H i j k'); omega.
Qed.

Lemma tm_closed_upgrade_freef: forall i j k k' t,
 tm_closed i j k t ->
 k' >= k ->
 tm_closed i j k' t.
Proof.
 intros. apply ((proj2 closed_inc_mult) t i j k H i j k'); omega.
Qed.

Lemma peval_extend : forall H t T v,
                       peval H t T ->
                       peval (v::H) t T.

Proof.
  intros H t T v Hp. unfold peval in Hp.
  destruct Hp as [Hcl [Hreq Hev]]. destruct Hev as [n Hev].
  unfold peval. split; try split; simpl.
  - eapply tm_closed_upgrade_freef; eauto.
  - omega.
  - exists n. rewrite false_beq_nat; try omega. apply Hev.
Qed.

Lemma teval_app_cmp: forall n H t1 t2 v v0 l t t0,
  teval n (v0 :: l) t0 = Some (Some v) ->
  teval n H t1 = Some (Some (vabs l t t0)) ->
  teval n H t2 = Some (Some v0) ->
  teval (S n) H (tapp t1 t2) = Some (Some v).
Proof.
  intros n. induction n; intros. simpl in *. solve by inversion.
  remember (S n) as n1. simpl. rewrite H1. rewrite H2. rewrite H0.
  reflexivity.
Qed.

Lemma teval_app_dcmp: forall n H t1 t2 v,
  teval n H (tapp t1 t2) = Some (Some v) ->
  exists n0 v0 l t t0,
  S n0 = n /\
  teval n0 (v0 :: l) t0 = Some (Some v) /\
  teval n0 H t1 = Some (Some (vabs l t t0)) /\
  teval n0 H t2 = Some (Some v0).
Proof.
  intros n. induction n; intros. simpl in *. solve by inversion.
  simpl in H0.

  remember (teval n H t2) as v2.
  destruct v2; simpl in H0; try solve [inversion H0].
  destruct o; simpl in H0; try solve [inversion H0].
  remember (teval n H t1) as v1.
  destruct v1; simpl in H0; try solve [inversion H0].
  destruct o; simpl in H0; try solve [inversion H0].
  destruct v1; simpl in H0; try solve [inversion H0].

  exists n. repeat eexists; eauto.
Qed.

Lemma teval_val_monotonic: forall n t H v n0,
  teval n0 H t = Some (Some v) -> n0 <= n -> teval n H t = Some (Some v).
Proof.
  intros n. induction n; intros.
  assert (n0 = 0) by omega. subst. simpl in H0. solve [inversion H0].
  destruct n0. simpl in H0. solve [inversion H0].

  destruct t; try solve [simpl; eauto].
  eapply teval_app_dcmp in H0. repeat ev.

  eapply teval_app_cmp.
  eapply IHn. eassumption. omega.
  eapply IHn. eassumption. omega.
  eapply IHn. eassumption. omega.
Qed.

Lemma teval_val_unique: forall n1 n2 t H v1 v2,
  teval n1 H t = Some (Some v1) -> teval n2 H t = Some (Some v2) -> v1 = v2.
Proof.
  intros n1 n2 t H v1 v2 Ev1 Ev2.
  assert (n1 <= n2 \/ n2 <= n1) as M. {
    destruct (le_or_lt n1 n2) as [A | A]; omega.
  }
  destruct M as [LE12 | LE21].
  - apply (teval_val_monotonic n2) in Ev1; try omega.
    rewrite Ev1 in Ev2. inversion Ev2. subst. reflexivity.
  - apply (teval_val_monotonic n1) in Ev2; try omega.
    rewrite Ev1 in Ev2. inversion Ev2. subst. reflexivity.
Qed.

Lemma peval_unique: forall H t v1 v2,
  peval H t v1 -> peval H t v2 -> v1 = v2.
Proof.
  intros H t v1 v2 Hp1 Hp2. unfold peval in *.
  destruct Hp1 as [Hc1 [Hr1 [n1 He1]]]. destruct Hp2 as [Hc2 [Hr2 [n2 He2]]].
  eapply teval_val_unique; eauto.
Qed.

Lemma join_env_extend1 : forall {X:Type} G1 G2 G (v:X),
                           join_env G1 G2 G ->
                           join_env (v::G1) G2 G.
Proof.
  unfold join_env. intros. destruct H as [G1' [G2' [H1 H2]]].
  exists (v::G1'). exists G2'. subst. split; eauto.
Qed.

Lemma join_env_extend2 : forall {X:Type} G1 G2 G (v:X),
                           join_env G1 G2 G ->
                           join_env G1 (v::G2) G.
Proof.
  unfold join_env. intros. destruct H as [G1' [G2' [H1 H2]]].
  exists G1'. exists (v::G2'). subst. split; eauto.
Qed.

(* splicing -- for stp_extend. *)

Fixpoint var_splice n (v: var) {struct v} : var :=
  match v with
    | varF x => varF x
    | varH i => if le_lt_dec n i then varH (i+1) else (varH i)
    | varB x => varB x
  end.
Fixpoint splice n (T : ty) {struct T} : ty :=
  match T with
    | TTop         => TTop
    | TBot         => TBot
    | TAll T1 T2   => TAll (splice n T1) (splice n T2)
    | TSel t       => TSel (tm_splice n t)
    | TMem T1 T2   => TMem (splice n T1) (splice n T2)
  end
with tm_splice n (t : tm) {struct t} : tm :=
  match t with
    | tvar v       => tvar (var_splice n v)
    | ttyp T       => ttyp (splice n T)
    | tabs T t     => tabs (splice n T) (tm_splice n t)
    | tapp t1 t2   => tapp (tm_splice n t1) (tm_splice n t2)
  end.

Definition spliceat n (V: (venv*ty)) :=
  match V with
    | (G,T) => (G,splice n T)
  end.

Lemma splice_open_commute:
  (forall T2 x n j, splice n (open_rec j x T2) = open_rec j (tm_splice n x) (splice n T2)) /\
  (forall t2 x n j, tm_splice n (tm_open_rec j x t2) = tm_open_rec j (tm_splice n x) (tm_splice n t2)).
Proof.
  apply tytm_mutind; intros; simpl; eauto; repeat rewrite H; repeat rewrite H0; eauto.
  destruct v; eauto.
  simpl.
  case_eq (le_lt_dec n i); intros; eauto.
  case_eq (beq_nat j i); intros E; simpl; eauto; rewrite E; eauto.
Qed.

Lemma splice_open_permute: forall {X} (G0:list X),
 (forall T2 n j,
  (open_rec j (tvar (varH (n + S (length G0)))) (splice (length G0) T2)) =
  (splice (length G0) (open_rec j (tvar (varH (n + length G0))) T2))) /\
 (forall t n j,
  (tm_open_rec j (tvar (varH (n + S (length G0)))) (tm_splice (length G0) t)) =
  (tm_splice (length G0) (tm_open_rec j (tvar (varH (n + length G0))) t))).
Proof.
  intros. split; intros; assert (n + S (length G0) = n + length G0 + 1) as A by omega;
  try rewrite (proj1 splice_open_commute); try rewrite (proj2 splice_open_commute);
  simpl; case_eq (le_lt_dec (length G0) (n + length G0)); intros;
  try rewrite A; eauto; omega.
Qed.

Lemma index_splice_hi: forall G0 G2 x0 v1 T,
    index x0 (G2 ++ G0) = Some T ->
    length G0 <= x0 ->
    index (x0 + 1) (map (splice (length G0)) G2 ++ v1 :: G0) = Some (splice (length G0) T).
Proof.
  intros G0 G2. induction G2; intros.
  - eapply index_max in H. simpl in H. omega.
  - simpl in H.
    case_eq (beq_nat x0 (length (G2 ++ G0))); intros E.
    + rewrite E in H. inversion H. subst. simpl.
      rewrite app_length in E.
      rewrite app_length. rewrite map_length. simpl.
      assert (beq_nat (x0 + 1) (length G2 + S (length G0)) = true). {
        eapply beq_nat_true_iff. eapply beq_nat_true_iff in E. omega.
      }
      rewrite H1. eauto.
    + rewrite E in H.  eapply IHG2 in H. eapply index_extend. eapply H. eauto.
Qed.

Lemma index_spliceat_hi: forall G0 G2 x0 v1 G T,
    index x0 (G2 ++ G0) = Some (G, T) ->
    length G0 <= x0 ->
    index (x0 + 1) (map (spliceat (length G0)) G2 ++ v1 :: G0) =
    Some (G, splice (length G0) T).
Proof.
  intros G0 G2. induction G2; intros.
  - eapply index_max in H. simpl in H. omega.
  - simpl in H. destruct a.
    case_eq (beq_nat x0 (length (G2 ++ G0))); intros E.
    + rewrite E in H. inversion H. subst. simpl.
      rewrite app_length in E.
      rewrite app_length. rewrite map_length. simpl.
      assert (beq_nat (x0 + 1) (length G2 + S (length G0)) = true). {
        eapply beq_nat_true_iff. eapply beq_nat_true_iff in E. omega.
      }
      rewrite H1. eauto.
    + rewrite E in H.  eapply IHG2 in H. eapply index_extend. eapply H. eauto.
Qed.

Lemma plus_lt_contra: forall a b,
  a + b < b -> False.
Proof.
  intros a b H. induction a.
  - simpl in H. apply lt_irrefl in H. assumption.
  - simpl in H. apply IHa. omega.
Qed.

Lemma index_splice_lo0: forall {X} G0 G2 x0 (T:X),
    index x0 (G2 ++ G0) = Some T ->
    x0 < length G0 ->
    index x0 G0 = Some T.
Proof.
  intros X G0 G2. induction G2; intros.
  - simpl in H. apply H.
  - simpl in H.
    case_eq (beq_nat x0 (length (G2 ++ G0))); intros E.
    + eapply beq_nat_true_iff in E. subst.
      rewrite app_length in H0. apply plus_lt_contra in H0. inversion H0.
    + rewrite E in H. apply IHG2. apply H. apply H0.
Qed.

Lemma index_extend_mult: forall {X} G0 G2 x0 (T:X),
    index x0 G0 = Some T ->
    index x0 (G2++G0) = Some T.
Proof.
  intros X G0 G2. induction G2; intros.
  - simpl. assumption.
  - simpl.
    case_eq (beq_nat x0 (length (G2 ++ G0))); intros E.
    + eapply beq_nat_true_iff in E.
      apply index_max in H. subst.
      rewrite app_length in H. apply plus_lt_contra in H. inversion H.
    + apply IHG2. assumption.
Qed.

Lemma index_splice_lo: forall G0 G2 x0 v1 T f,
    index x0 (G2 ++ G0) = Some T ->
    x0 < length G0 ->
    index x0 (map (splice f) G2 ++ v1 :: G0) = Some T.
Proof.
  intros.
  assert (index x0 G0 = Some T). eapply index_splice_lo0; eauto.
  eapply index_extend_mult. eapply index_extend. eauto.
Qed.

Lemma index_spliceat_lo: forall G0 G2 x0 v1 G T f,
    index x0 (G2 ++ G0) = Some (G, T) ->
    x0 < length G0 ->
    index x0 (map (spliceat f) G2 ++ v1 :: G0) = Some (G, T).
Proof.
  intros.
  assert (index x0 G0 = Some (G, T)). eapply index_splice_lo0; eauto.
  eapply index_extend_mult. eapply index_extend. eauto.
Qed.

Lemma closed_splice:
  (forall T i j k n, closed i j k T -> closed i (S j) k (splice n T)) /\
  (forall t i j k n, tm_closed i j k t -> tm_closed i (S j) k (tm_splice n t)).
Proof.
  apply tytm_mutind; intros; simpl; eauto;
  try solve [inversion H1; subst; econstructor; eauto];
  try solve [inversion H0; subst; econstructor; eauto].
  inversion H; subst. econstructor.
  inversion H4; subst.
  simpl; econstructor; omega.
  simpl. case_eq (le_lt_dec n x); intros; econstructor; omega.
  simpl; econstructor; omega.
Qed.

Lemma map_splice_length_inc: forall G0 G2 v1,
   (length (map (splice (length G0)) G2 ++ v1 :: G0)) = (S (length (G2 ++ G0))).
Proof.
  intros. rewrite app_length. rewrite map_length. induction G2.
  - simpl. reflexivity.
  - simpl. eauto.
Qed.

Lemma map_spliceat_length_inc: forall G0 G2 v1,
   (length (map (spliceat (length G0)) G2 ++ v1 :: G0)) = (S (length (G2 ++ G0))).
Proof.
  intros. rewrite app_length. rewrite map_length. induction G2.
  - simpl. reflexivity.
  - simpl. eauto.
Qed.

Lemma closed_splice_idem:
  (forall T i j k n,
    closed i j k T ->
    n >= j ->
    splice n T = T) /\
  (forall t i j k n,
    tm_closed i j k t ->
    n >= j ->
    tm_splice n t = t).
Proof.
  apply tytm_mutind; intros; eauto;
  try solve [inversion H1; simpl; repeat erewrite H; repeat erewrite H0; eauto];
  try solve [inversion H0; simpl; repeat erewrite H; repeat erewrite H0; eauto].
  simpl. f_equal. inversion H; subst. inversion H5; subst; eauto.
  simpl. case_eq (le_lt_dec n x); intros E LE; eauto. omega.
Qed.

Ltac inv_mem := match goal with
                  | H: closed 0 (length ?GH) (length ?G) (TMem ?T1 ?T2) |-
                    closed 0 (length ?GH) (length ?G) ?T2 => inversion H; subst; eauto
                  | H: closed 0 (length ?GH) (length ?G) (TMem ?T1 ?T2) |-
                    closed 0 (length ?GH) (length ?G) ?T1 => inversion H; subst; eauto
                end.

Scheme stp_mut := Induction for stp Sort Prop
with   hastp_mut := Induction for has_type Sort Prop.
Combined Scheme tp_mutind from stp_mut, hastp_mut.

Lemma tp_closed  :
  (forall G GH T1 T2, stp G GH T1 T2 -> closed 0 (length GH) (length G) T1 /\ closed 0 (length GH) (length G) T2) /\
  (forall G GH t T, has_type G GH t T -> tm_closed 0 (length GH) (length G) t /\ closed 0 (length GH) (length G) T).
Proof.
  apply tp_mutind; intros; eauto; repeat ev; split;
  try solve [try inv_mem; eauto using index_max];
  try solve [repeat econstructor; eauto using index_max; eapply (proj1 closed_inc_mult); eauto; omega].
Qed.

Lemma stp_closed : forall G GH T1 T2,
                     stp G GH T1 T2 ->
                     closed 0 (length GH) (length G) T1 /\ closed 0 (length GH) (length G) T2.
Proof.
  intros. apply (proj1 tp_closed). eauto.
Qed.

Lemma stp_closed2 : forall G1 GH T1 T2,
                       stp G1 GH T1 T2 ->
                       closed 0 (length GH) (length G1) T2.
Proof.
  intros. apply (proj2 (stp_closed G1 GH T1 T2 H)).
Qed.

Lemma stp_closed1 : forall G1 GH T1 T2,
                       stp G1 GH T1 T2 ->
                       closed 0 (length GH) (length G1) T1.
Proof.
  intros. apply (proj1 (stp_closed G1 GH T1 T2 H)).
Qed.

Lemma peval_closed: forall G1 t v,
                      peval G1 t v ->
                      tm_closed 0 0 (length G1) t.
Proof.
  intros. unfold peval in H. destruct H as [Hc ?]. eapply Hc.
Qed.

Lemma stp2_closed: forall G1 G2 T1 T2 GH s m n,
                     stp2 s m G1 T1 G2 T2 GH n ->
                     closed 0 (length GH) (length G1) T1 /\ closed 0 (length GH) (length G2) T2.
  intros. induction H;
    try solve [repeat ev; split; try inv_mem; eauto using index_max, peval_closed;
               try solve [econstructor; eapply (proj2 closed_inc_mult); eauto using peval_closed; omega];
               try solve [repeat econstructor; eauto using index_max, peval_closed]].
  unfold join_env in H. destruct H as [G1' [G2' [H1' H2']]]. subst.
  repeat rewrite app_length. split;
  econstructor; eapply (proj2 closed_inc_mult); eauto; omega.
Qed.

Lemma stp2_closed2 : forall G1 G2 T1 T2 GH s m n,
                       stp2 s m G1 T1 G2 T2 GH n ->
                       closed 0 (length GH) (length G2) T2.
Proof.
  intros. apply (proj2 (stp2_closed G1 G2 T1 T2 GH s m n H)).
Qed.

Lemma stp2_closed1 : forall G1 G2 T1 T2 GH s m n,
                       stp2 s m G1 T1 G2 T2 GH n ->
                       closed 0 (length GH) (length G1) T1.
Proof.
  intros. apply (proj1 (stp2_closed G1 G2 T1 T2 GH s m n H)).
Qed.

Lemma closed_open:
  (forall T i j k V, closed (i+1) j k T -> tm_closed i j k V -> closed i j k (open_rec i V T)) /\
  (forall t i j k V, tm_closed (i+1) j k t -> tm_closed i j k V -> tm_closed i j k (tm_open_rec i V t)).
Proof.
  apply tytm_mutind; intros;
  try solve [try (inversion H1; subst); try (inversion H0; subst);
             simpl; econstructor; eauto;
             try (try eapply H0; try eapply H; eauto; eapply (proj2 closed_inc_mult); eauto; omega)].
  simpl. inversion H; subst.
  inversion H5; subst; simpl; try solve [econstructor; econstructor; omega].
  case_eq (beq_nat i x); intros E; eauto.
  econstructor. econstructor. apply beq_nat_false in E. omega.
Qed.

Lemma index_has: forall X (G: list X) x,
  length G > x ->
  exists v, index x G = Some v.
Proof.
  intros. remember (length G) as n.
  generalize dependent x.
  generalize dependent G.
  induction n; intros; try omega.
  destruct G; simpl.
  - simpl in Heqn. inversion Heqn.
  - simpl in Heqn. inversion Heqn. subst.
    case_eq (beq_nat x (length G)); intros E.
    + eexists. reflexivity.
    + apply beq_nat_false in E. apply IHn; eauto.
      omega.
Qed.

Lemma stp_refl_aux: forall n T G GH,
  closed 0 (length GH) (length G) T ->
  tsize T < n ->
  stp G GH T T.
Proof.
  intros n. induction n; intros; try omega.
  inversion H; subst; eauto;
  try solve [omega];
  try solve [simpl in H0; constructor; apply IHn; eauto; try omega];
  try solve [apply index_has in H1; destruct H1; eauto].
  - simpl in H0.
    eapply stp_all.
    eapply IHn; eauto; try omega.
    reflexivity.
    assumption.
    assumption.
    apply IHn; eauto.
    simpl. apply (proj1 closed_open); auto using closed_inc.
    unfold open. rewrite <- (proj1 open_preserves_size). omega.
Qed.

Lemma stp_refl: forall T G GH,
  closed 0 (length GH) (length G) T ->
  stp G GH T T.
Proof.
  intros. apply stp_refl_aux with (n:=S (tsize T)); eauto.
Qed.

Definition stpd2 s m G1 T1 G2 T2 GH := exists n, stp2 s m G1 T1 G2 T2 GH n.

Ltac ep := match goal with
             | [ |- stp2 ?S ?M ?G1 ?T1 ?G2 ?T2 ?GH ?N ] =>
               assert (exists (n:nat), stp2 S M G1 T1 G2 T2 GH n) as EEX
           end.

Ltac eu := match goal with
             | H: stpd2 _ _ _ _ _ _ _ |- _ =>
               destruct H as [? H]
           end.

Hint Unfold stpd2.

Lemma stp2_refl_aux: forall n T G GH s,
  closed 0 (length GH) (length G) T ->
  tsize T < n ->
  stpd2 s true G T G T GH.
Proof.
  intros n. induction n; intros; try omega.
  inversion H; subst; eauto; try omega; try simpl in H0.
  - destruct (IHn T1 G GH false) as [n1 IH1]; eauto; try omega.
    destruct (IHn (open (tvar (varH (length GH))) T2) G ((G,T1)::GH) false); eauto; try omega.
    simpl. apply closed_open; auto using closed_inc.
    unfold open. rewrite <- (proj1 open_preserves_size). omega.
    eexists; econstructor; try constructor; eauto.
  - eexists; eapply stp2_selxr; eauto.
    unfold join_env. exists []. exists []. rewrite app_nil_l. split; reflexivity.
  - destruct (IHn T1 G GH s) as [n1 IH1]; eauto; try omega.
    destruct (IHn T2 G GH s) as [n2 IH2]; eauto; try omega.
    destruct s; eexists; econstructor; try constructor; eauto.
Grab Existential Variables. apply 0. apply 0. apply 0.
Qed.

Lemma stp2_refl: forall T G GH s,
  closed 0 (length GH) (length G) T ->
  stpd2 s true G T G T GH.
Proof.
  intros. apply stp2_refl_aux with (n:=S (tsize T)); eauto.
Qed.

Lemma concat_same_length: forall {X} (GU: list X) (GL: list X) (GH1: list X) (GH0: list X),
  GU ++ GL = GH1 ++ GH0 ->
  length GU = length GH1 ->
  GU=GH1 /\ GL=GH0.
Proof.
  intros. generalize dependent GH1. induction GU; intros.
  - simpl in H0. induction GH1. rewrite app_nil_l in H. rewrite app_nil_l in H.
    split. reflexivity. apply H.
    simpl in H0. omega.
  - simpl in H0. induction GH1. simpl in H0. omega.
    simpl in H0. inversion H0. simpl in H. inversion H. specialize (IHGU GH1 H4 H2).
    destruct IHGU. subst. split; reflexivity.
Qed.

Lemma concat_same_length': forall {X} (GU: list X) (GL: list X) (GH1: list X) (GH0: list X),
  GU ++ GL = GH1 ++ GH0 ->
  length GL = length GH0 ->
  GU=GH1 /\ GL=GH0.
Proof.
  intros.
  assert (length (GU ++ GL) = length (GH1 ++ GH0)) as A. {
    rewrite H. reflexivity.
  }
  rewrite app_length in A. rewrite app_length in A.
  rewrite H0 in A. apply NPeano.Nat.add_cancel_r in A.
  apply concat_same_length; assumption.
Qed.

Lemma exists_GH1L: forall {X} (GU: list X) (GL: list X) (GH1: list X) (GH0: list X) x0,
  length GL = x0 ->
  GU ++ GL = GH1 ++ GH0 ->
  length GH0 <= x0 ->
  exists GH1L, GH1 = GU ++ GH1L /\ GL = GH1L ++ GH0.
Proof.
  intros X GU. induction GU; intros.
  - eexists. rewrite app_nil_l. split. reflexivity. simpl in H0. assumption.
  - induction GH1.

    simpl in H0.
    assert (length (a :: GU ++ GL) = length GH0) as Contra. {
      rewrite H0. reflexivity.
    }
    simpl in Contra. rewrite app_length in Contra. omega.

    simpl in H0. inversion H0.
    specialize (IHGU GL GH1 GH0 x0 H H4 H1).
    destruct IHGU as [GH1L [IHA IHB]].
    exists GH1L. split. simpl. rewrite IHA. reflexivity. apply IHB.
Qed.

Lemma exists_GH0U: forall {X} (GH1: list X) (GH0: list X) (GU: list X) (GL: list X) x0,
  length GL = x0 ->
  GU ++ GL = GH1 ++ GH0 ->
  x0 < length GH0 ->
  exists GH0U, GH0 = GH0U ++ GL.
Proof.
  intros X GH1. induction GH1; intros.
  - simpl in H0. exists GU. symmetry. assumption.
  - induction GU.

    simpl in H0.
    assert (length GL = length (a :: GH1 ++ GH0)) as Contra. {
      rewrite H0. reflexivity.
    }
    simpl in Contra. rewrite app_length in Contra. omega.

    simpl in H0. inversion H0.
    specialize (IHGH1 GH0 GU GL x0 H H4 H1).
    destruct IHGH1 as [GH0U IH].
    exists GH0U. apply IH.
Qed.

Lemma stp_splice :
  (forall GX G T1 T2,
   stp GX G T1 T2 -> forall G0 G1 v1, G=G1++G0 ->
   stp GX ((map (splice (length G0)) G1) ++ v1::G0)
       (splice (length G0) T1) (splice (length G0) T2)) /\
  (forall GX G t T,
   has_type GX G t T -> forall G0 G1 v1, G=G1++G0 ->
   has_type GX ((map (splice (length G0)) G1) ++ v1::G0)
       (tm_splice (length G0) t) (splice (length G0) T)).
Proof.
  apply tp_mutind; intros; simpl; eauto.
  - Case "top".
    eapply stp_top.
    rewrite map_splice_length_inc.
    apply closed_splice.
    subst. assumption.
  - Case "bot".
    eapply stp_bot.
    rewrite map_splice_length_inc.
    apply closed_splice.
    subst. assumption.
  - Case "sel1".
    eapply stp_sel1. apply H. assumption. simpl in H0. apply H0. assumption.
  - Case "sel2".
    eapply stp_sel2. apply H. assumption. simpl in H0. apply H0. assumption.
  - Case "sela1".
    case_eq (le_lt_dec (length G0) x); intros E LE.
    + eapply stp_sela1.
      apply index_splice_hi. subst. eauto. eauto.
      assert (S x = x +1) as A by omega.
      rewrite <- A. eapply (proj1 closed_splice). eauto.
      eapply H. eauto.
    + eapply stp_sela1. eapply index_splice_lo. subst. eauto. eauto. eauto.
      assert (splice (length G0) TX=TX) as A. {
        eapply closed_splice_idem. eassumption. omega.
      }
      rewrite <- A. eapply H. eauto.
  - Case "sela2".
    case_eq (le_lt_dec (length G0) x); intros E LE.
    + eapply stp_sela2.
      apply index_splice_hi. subst. eauto. eauto.
      assert (S x = x +1) as A by omega.
      rewrite <- A. eapply closed_splice. auto.
      eapply H. eauto.
    + eapply stp_sela2. eapply index_splice_lo. subst. eauto. eauto. eauto.
      assert (splice (length G0) TX=TX) as A. {
        eapply closed_splice_idem. eassumption. omega.
      }
      rewrite <- A. eapply H. eauto.
  - Case "selx".
    eapply stp_selx.
    rewrite map_splice_length_inc.
    apply closed_splice.
    subst. assumption.
  - Case "all".
    eapply stp_all.
    eapply H. eauto. eauto.
    simpl. rewrite map_splice_length_inc. apply closed_splice. subst. assumption.
    simpl. rewrite map_splice_length_inc. apply closed_splice. subst. assumption.
    specialize H0 with (G0:=G0) (G2:=T3 :: G2). simpl in H0.
    rewrite app_length. rewrite map_length. simpl.
    repeat rewrite (proj1 (splice_open_permute G0)) with (j:=0). subst.
    rewrite app_length in H0. simpl in H0. eapply H0. eauto.
  - erewrite (proj1 closed_splice_idem); eauto. omega.
(*
  - case_eq (le_lt_dec (length G0) x); intros E LE; subst.
    + eapply t_varH. apply index_splice_hi; eauto.
      assert (S x = x + 1) as A by omega. rewrite <- A.
      apply (proj1 closed_splice); eauto.
    + eapply t_varH. apply index_splice_lo; eauto.
      erewrite (proj1 closed_splice_idem); eauto. omega.
      erewrite (proj1 closed_splice_idem); eauto. omega.
*)
  - eapply t_typ.
    simpl. rewrite map_splice_length_inc. apply closed_splice. subst. assumption.
  - eapply t_app; eauto. subst.
    unfold open. rewrite (proj1 splice_open_commute). reflexivity.
    simpl. rewrite map_splice_length_inc. apply closed_splice. subst. assumption.
  - subst.
    assert (splice (length G0) T1 = T1) as C. {
      erewrite (proj1 closed_splice_idem). reflexivity. eauto. omega.
    }
    assert (tvar (varF (length G1))=tm_splice (length G0) (tvar (varF (length G1)))) as B. {
      erewrite (proj2 closed_splice_idem). reflexivity.
      econstructor. econstructor. eauto. eauto.
    }
    assert (TAll (splice (length G0) T1) (splice (length G0) T2) =
            splice (length G0) (TAll T1 T2)) as A by eauto.
    eapply t_abs; eauto.
    rewrite B. unfold open. rewrite <- (proj1 splice_open_commute).
    rewrite C. eapply H; eauto. rewrite C. assumption.
    simpl. rewrite map_splice_length_inc. rewrite A. apply (proj1 closed_splice).
    assumption.
Grab Existential Variables.
apply 0.
Qed.

Lemma stp2_splice : forall G1 T1 G2 T2 GH1 GH0 v1 s m n,
   stp2 s m G1 T1 G2 T2 (GH1++GH0) n ->
   stp2 s m G1 (splice (length GH0) T1) G2 (splice (length GH0) T2)
        ((map (spliceat (length GH0)) GH1) ++ v1::GH0) n.
Proof.
  intros G1 T1 G2 T2 GH1 GH0 v1 s m n H. remember (GH1++GH0) as GH.
  revert GH0 GH1 HeqGH.
  induction H; intros; subst GH; simpl; eauto.
  - Case "top".
    eapply stp2_top.
    rewrite map_spliceat_length_inc.
    apply closed_splice.
    assumption.
  - Case "bot".
    eapply stp2_bot.
    rewrite map_spliceat_length_inc.
    apply closed_splice.
    assumption.
  - Case "strong_sel1".
    assert (splice (length GH0) TX=TX) as A. {
      eapply closed_splice_idem. eassumption. omega.
    }
    assert (tm_splice (length GH0) t=t) as B. {
      eapply closed_splice_idem. eapply peval_closed. eassumption. omega.
    }
    rewrite B.
    eapply stp2_strong_sel1; eauto.
    rewrite <- A. eapply IHstp2; eauto.
  - Case "strong_sel2".
    assert (splice (length GH0) TX=TX) as A. {
      eapply closed_splice_idem. eassumption. omega.
    }
    assert (tm_splice (length GH0) t=t) as B. {
      eapply closed_splice_idem. eapply peval_closed. eassumption. omega.
    }
    rewrite B.
    eapply stp2_strong_sel2; eauto.
    rewrite <- A. eapply IHstp2; eauto.
  - Case "sel1".
    assert (splice (length GH0) TX=TX) as A. {
      eapply closed_splice_idem. eassumption. omega.
    }
    assert (tm_splice (length GH0) t=t) as B. {
      eapply closed_splice_idem. eapply peval_closed. eassumption. omega.
    }
    rewrite B.
    eapply stp2_sel1; eauto.
    rewrite <- A. apply IHstp2; eauto.
  - Case "sel2".
    assert (splice (length GH0) TX=TX) as A. {
      eapply closed_splice_idem. eassumption. omega.
    }
    assert (tm_splice (length GH0) t=t) as B. {
      eapply closed_splice_idem. eapply peval_closed. eassumption. omega.
    }
    rewrite B.
    eapply stp2_sel2; eauto.
    rewrite <- A. apply IHstp2; eauto.
  - Case "selxr".
    eapply stp2_selxr. eassumption.
    rewrite map_spliceat_length_inc. eapply closed_splice. eassumption.
  - Case "selx".
    assert (tm_splice (length GH0) t1=t1) as A. {
      eapply closed_splice_idem. eapply peval_closed. eassumption. omega.
    }
    assert (tm_splice (length GH0) t2=t2) as B. {
      eapply closed_splice_idem. eapply peval_closed. eassumption. omega.
    }
    rewrite A. rewrite B. eapply stp2_selx; eauto.
  - Case "sela1".
    case_eq (le_lt_dec (length GH0) x); intros E LE.
    + eapply stp2_sela1.
      eapply index_spliceat_hi. apply H. eauto.
      eapply closed_splice in H0. assert (S x = x + 1) by omega. rewrite <- H2.
      eapply H0.
      eapply IHstp2. eauto.
    + eapply stp2_sela1. eapply index_spliceat_lo. apply H. eauto. eauto.
      assert (splice (length GH0) TX=TX) as A. {
        eapply closed_splice_idem. eassumption. omega.
      }
      rewrite <- A. eapply IHstp2. eauto.
  - Case "sela2".
    case_eq (le_lt_dec (length GH0) x); intros E LE.
    + eapply stp2_sela2.
      eapply index_spliceat_hi. apply H. eauto.
      eapply closed_splice in H0. assert (S x = x + 1) by omega. rewrite <- H2.
      eapply H0.
      eapply IHstp2. eauto.
    + eapply stp2_sela2. eapply index_spliceat_lo. apply H. eauto. eauto.
      assert (splice (length GH0) TX=TX) as A. {
        eapply closed_splice_idem. eassumption. omega.
      }
      rewrite <- A. eapply IHstp2. eauto.
(*
  - Case "selax".
    case_eq (le_lt_dec (length GH0) x); intros E LE.
    + destruct v. eapply stp2_selax.
      eapply index_spliceat_hi. apply H. eauto.
    + destruct v. eapply stp2_selax.
      eapply index_spliceat_lo. apply H. eauto.
*)
  - Case "all".
    apply stp2_all with (x:= length GH1 + S (length GH0)).
    eapply IHstp2_1. reflexivity.

    simpl. rewrite map_spliceat_length_inc. rewrite app_length. omega.
    simpl. rewrite map_spliceat_length_inc. apply closed_splice. assumption.
    simpl. rewrite map_spliceat_length_inc. apply closed_splice. assumption.

    subst x.
    specialize IHstp2_2 with (GH2:=GH0) (GH3:=(G2, T3) :: GH1).
    simpl in IHstp2_2.
    repeat rewrite (proj1 (splice_open_permute GH0)) with (j:=0).
    rewrite app_length in IHstp2_2.
    eapply IHstp2_2. reflexivity.
Qed.

Lemma stp_extend :
  (forall G1 GH T1 T2,
    stp G1 GH T1 T2 -> forall v1,
    stp G1 (v1::GH) T1 T2) /\
  (forall G1 GH t1 T2,
    has_type G1 GH t1 T2 -> forall v1,
    has_type G1 (v1::GH) t1 T2).
Proof.
  apply tp_mutind; intros; eauto using index_extend, closed_inc, tm_closed_inc.
  assert (splice (length GH) T2 = T2) as A2. {
    eapply closed_splice_idem. eauto. omega.
  }
  assert (splice (length GH) T4 = T4) as A4. {
    eapply closed_splice_idem. eauto. omega.
  }
  assert (closed 0 (length GH) (length G1) T3). eapply stp_closed1. eauto.
  assert (splice (length GH) T3 = T3) as A3. {
    eapply closed_splice_idem. eauto. omega.
  }
  assert (map (splice (length GH)) [T3] ++ v1::GH =
          (T3::v1::GH)) as HGX3. {
    simpl. rewrite A3. eauto.
  }
  apply stp_all with (x:=length (v1 :: GH)).
  apply H.
  reflexivity.
  apply closed_inc. eauto.
  apply closed_inc. eauto.
  simpl.
  rewrite <- A2. rewrite <- A4.
  unfold open.
  change (varH (S (length GH))) with (varH (0 + (S (length GH)))).
  repeat rewrite -> (proj1 (splice_open_permute GH)).
  rewrite <- HGX3.
  eapply (proj1 stp_splice).
  simpl. unfold open in s0. rewrite <- e. apply s0. eauto.
Qed.

Lemma stp_extend_mult : forall G T1 T2 GH GH2,
                       stp G GH T1 T2 ->
                       stp G (GH2++GH) T1 T2.
Proof.
  intros. induction GH2.
  - simpl. assumption.
  - simpl.
    apply stp_extend. assumption.
Qed.

Lemma index_at_index: forall {A} x0 GH0 GH1 (v:A),
  beq_nat x0 (length GH1) = true ->
  index x0 (GH0 ++ v :: GH1) = Some v.
Proof.
  intros. apply beq_nat_true in H. subst.
  induction GH0.
  - simpl. rewrite <- beq_nat_refl. reflexivity.
  - simpl.
    rewrite app_length. simpl. rewrite <- plus_n_Sm. rewrite <- plus_Sn_m.
    rewrite false_beq_nat. assumption. omega.
Qed.

Lemma index_same: forall {A} x0 (v0:A) GH0 GH1 (v:A) (v':A),
  beq_nat x0 (length GH1) = false ->
  index x0 (GH0 ++ v :: GH1) = Some v0 ->
  index x0 (GH0 ++ v' :: GH1) = Some v0.
Proof.
  intros ? ? ? ? ? ? ? E H.
  induction GH0.
  - simpl. rewrite E. simpl in H. rewrite E in H. apply H.
  - simpl.
    rewrite app_length. simpl.
    case_eq (beq_nat x0 (length GH0 + S (length GH1))); intros E'.
    simpl in H. rewrite app_length in H. simpl in H. rewrite E' in H.
    rewrite H. reflexivity.
    simpl in H. rewrite app_length in H. simpl in H. rewrite E' in H.
    rewrite IHGH0. reflexivity. assumption.
Qed.

Inductive venv_ext : venv -> venv -> Prop :=
| venv_ext_refl : forall G, venv_ext G G
| venv_ext_cons : forall T G1 G2, venv_ext G1 G2 -> venv_ext (T::G1) G2.

Inductive aenv_ext : aenv -> aenv -> Prop :=
| aenv_ext_nil : aenv_ext nil nil
| aenv_ext_cons :
    forall T G' G A A',
      aenv_ext A' A -> venv_ext G' G ->
      aenv_ext ((G',T)::A') ((G,T)::A).

Lemma aenv_ext_refl: forall GH, aenv_ext GH GH.
Proof.
  intros. induction GH.
  - apply aenv_ext_nil.
  - destruct a. apply aenv_ext_cons.
    assumption.
    apply venv_ext_refl.
Qed.

Lemma venv_ext__ge_length:
  forall G G',
    venv_ext G' G ->
    length G' >= length G.
Proof.
  intros. induction H; simpl; omega.
Qed.

Lemma aenv_ext__same_length:
  forall GH GH',
    aenv_ext GH' GH ->
    length GH = length GH'.
Proof.
  intros. induction H.
  - simpl. reflexivity.
  - simpl. rewrite IHaenv_ext. reflexivity.
Qed.

Lemma aenv_ext__concat:
  forall GH GH' GU GL,
    aenv_ext GH' GH ->
    GH = GU ++ GL ->
    exists GU' GL', GH' = GU' ++ GL' /\ aenv_ext GU' GU /\ aenv_ext GL' GL.
Proof.
  intros. generalize dependent GU. generalize dependent GL. induction H.
  - intros. symmetry in H0. apply app_eq_nil in H0. destruct H0.
    exists []. exists []. simpl. split; eauto. subst. split. apply aenv_ext_refl. apply aenv_ext_refl.
  - intros. induction GU. rewrite app_nil_l in H1. subst.
    exists []. eexists. rewrite app_nil_l. split. reflexivity.
    split. apply aenv_ext_refl.
    apply aenv_ext_cons. eassumption. eassumption.

    simpl in H1. inversion H1.
    specialize (IHaenv_ext GL GU H4).
    destruct IHaenv_ext as [GU' [GL' [IHA [IHU IHL]]]].
    exists ((G', T)::GU'). exists GL'.
    split. simpl. rewrite IHA. reflexivity.
    split. apply aenv_ext_cons. apply IHU. assumption. apply IHL.
Qed.

Lemma index_at_ext :
  forall GH GH' x T G,
    aenv_ext GH' GH ->
    index x GH = Some (G, T) ->
    exists G', index x GH' = Some (G', T) /\ venv_ext G' G.
Proof.
  intros GH GH' x T G Hext Hindex. induction Hext.
  - simpl in Hindex. inversion Hindex.
  - simpl. simpl in Hindex.
    case_eq (beq_nat x (length A)); intros E.
    rewrite E in Hindex.  inversion Hindex. subst.
    rewrite <- (@aenv_ext__same_length A A'). rewrite E.
    exists G'. split. reflexivity. assumption. assumption.
    rewrite E in Hindex.
    rewrite <- (@aenv_ext__same_length A A'). rewrite E.
    apply IHHext. assumption. assumption.
Qed.

Lemma index_extend_venv : forall G G' x T,
                       index x G = Some T ->
                       venv_ext G' G ->
                       index x G' = Some T.
Proof.
  intros G G' x T H HV.
  induction HV.
  - assumption.
  - apply index_extend. apply IHHV. apply H.
Qed.

Lemma peval_extend_venv : forall G G' x T,
                       peval G x T ->
                       venv_ext G' G ->
                       peval G' x T.
Proof.
  intros G G' x T H HV.
  induction HV.
  - assumption.
  - apply peval_extend. apply IHHV. apply H.
Qed.

Lemma venv_ext_prefix_ex : forall G G',
  venv_ext G' G ->
  exists l, G'=l++G.
Proof.
  intros. induction H; subst.
  - exists []. simpl. reflexivity.
  - destruct IHvenv_ext as [l Eq]. subst.
    exists (T::l). simpl. reflexivity.
Qed.

Lemma join_extend_venv : forall G1 G1' G2 G2' G,
  join_env G1 G2 G ->
  venv_ext G1' G1 ->
  venv_ext G2' G2 ->
  exists G', join_env G1' G2' G' /\ venv_ext G' G.
Proof.
  intros G1 G1' G2 G2' G Hj H1 H2. unfold join_env in Hj.
  destruct Hj as [l1 [l2 [Eq1 Eq2]]]. subst.
  apply venv_ext_prefix_ex in H1. apply venv_ext_prefix_ex in H2.
  destruct H1 as [l1' H1]. destruct H2 as [l2' H2]. subst.
  exists G. split.
  unfold join_env. exists (l1'++l1). exists (l2'++l2).
  split; rewrite app_assoc; reflexivity.
  apply venv_ext_refl.
Qed.

Lemma stp2_closure_extend_rec:
  forall G1 G2 T1 T2 GH s m n,
    stp2 s m G1 T1 G2 T2 GH n ->
    (forall G1' G2' GH',
       aenv_ext GH' GH ->
       venv_ext G1' G1 ->
       venv_ext G2' G2 ->
       stp2 s m G1' T1 G2' T2 GH' n).
Proof.
  intros G1 G2 T1 T2 GH s m n H.
  induction H; intros; eauto.
  - Case "top".
    eapply stp2_top.
    eapply closed_inc_mult; try eassumption; try omega.
    rewrite (@aenv_ext__same_length GH GH'). omega. assumption.
    apply venv_ext__ge_length. assumption.
  - Case "bot".
    eapply stp2_bot.
    eapply closed_inc_mult; try eassumption; try omega.
    rewrite (@aenv_ext__same_length GH GH'). omega. assumption.
    apply venv_ext__ge_length. assumption.
  - Case "strong_sel1".
    eapply stp2_strong_sel1. eapply peval_extend_venv. apply H. assumption.
    assumption. assumption.
    apply IHstp2. assumption. apply venv_ext_refl. assumption.
  - Case "strong_sel2".
    eapply stp2_strong_sel2. eapply peval_extend_venv. apply H. assumption.
    assumption. assumption.
    apply IHstp2. assumption. assumption. apply venv_ext_refl.
  - Case "sel1".
    eapply stp2_sel1. eapply peval_extend_venv. apply H. assumption.
    eassumption. assumption.
    apply IHstp2. assumption. apply venv_ext_refl. assumption.
  - Case "sel2".
    eapply stp2_sel2. eapply peval_extend_venv. apply H. assumption.
    eassumption. assumption.
    apply IHstp2. assumption. apply venv_ext_refl. assumption.
  - Case "selxr".
    eapply join_extend_venv in H; eauto. destruct H as [G' [H H']].
    eapply stp2_selxr; eauto.
    eapply closed_inc_mult; try eassumption; try omega.
    rewrite (@aenv_ext__same_length GH GH'). omega. assumption.
    apply venv_ext__ge_length. assumption.
  - Case "selx".
    eapply stp2_selx.
    eapply peval_extend_venv; try eassumption.
    eapply peval_extend_venv; try eassumption.
  - Case "sela1".
    assert (exists GX', index x GH' = Some (GX', TX) /\ venv_ext GX' GX) as A. {
      apply index_at_ext with (GH:=GH); assumption.
    }
    inversion A as [GX' [H' HX]].
    apply stp2_sela1 with (GX:=GX') (TX:=TX).
    assumption.
    eapply closed_inc_mult; try eassumption; try omega.
    apply venv_ext__ge_length. assumption.
    apply IHstp2; assumption.
  - Case "sela2".
    assert (exists GX', index x GH' = Some (GX', TX) /\ venv_ext GX' GX) as A. {
      apply index_at_ext with (GH:=GH); assumption.
    }
    inversion A as [GX' [H' HX]].
    apply stp2_sela2 with (GX:=GX') (TX:=TX).
    assumption.
    eapply closed_inc_mult; try eassumption; try omega.
    apply venv_ext__ge_length. assumption.
    apply IHstp2; assumption.
(*
  - Case "selax".
    destruct v as [GX TX].
    assert (exists GX', index x GH' = Some (GX', TX) /\ venv_ext GX' GX) as A. {
      apply index_at_ext with (GH:=GH); assumption.
    }
    inversion A as [GX' [H' HX]].
    apply stp2_selax with (v:=(GX',TX)).
    assumption.
*)
  - Case "all".
    eapply stp2_all with (x:=length GH').
    apply IHstp2_1; assumption.
    reflexivity.
    eapply closed_inc_mult; try eassumption; try omega.
    rewrite (@aenv_ext__same_length GH GH'). omega. assumption.
    apply venv_ext__ge_length. assumption.
    eapply closed_inc_mult; try eassumption; try omega.
    rewrite (@aenv_ext__same_length GH GH'). omega. assumption.
    apply venv_ext__ge_length. assumption.
    subst.  rewrite <- (@aenv_ext__same_length GH GH').
    apply IHstp2_2. apply aenv_ext_cons.
    assumption. assumption. assumption. assumption. assumption.
  - Case "trans".
    eapply stp2_transf.
    eapply IHstp2_1.
    assumption. assumption. apply venv_ext_refl.
    eapply IHstp2_2.
    assumption. apply venv_ext_refl. assumption.
Qed.

Lemma stp2_closure_extend : forall G1 T1 G2 T2 GH GX T v s m n,
                              stp2 s m G1 T1 G2 T2 ((GX,T)::GH) n ->
                              stp2 s m G1 T1 G2 T2 ((v::GX,T)::GH) n.
Proof.
  intros. eapply stp2_closure_extend_rec. apply H.
  apply aenv_ext_cons. apply aenv_ext_refl. apply venv_ext_cons.
  apply venv_ext_refl. apply venv_ext_refl. apply venv_ext_refl.
Qed.

Lemma stp2_extend : forall v1 G1 G2 T1 T2 H s m n,
                      stp2 s m G1 T1 G2 T2 H n ->
                       stp2 s m (v1::G1) T1 G2 T2 H n /\
                       stp2 s m G1 T1 (v1::G2) T2 H n /\
                       stp2 s m (v1::G1) T1 (v1::G2) T2 H n.
Proof.
  intros. induction H0;
    try destruct IHstp2 as [? [? ?]];
    try destruct IHstp2_1 as [? [? ?]];
    try destruct IHstp2_2 as [? [? ?]];
    split; try split; intros;
    try solve [eauto using peval_extend, close_upgrade_freef, tm_closed_upgrade_freef];
    try solve [econstructor; simpl; eauto using peval_extend, closed_upgrade_freef, tm_closed_upgrade_freef, join_env_extend1, join_env_extend2];
    try solve [eapply stp2_all; simpl; eauto using stp2_closure_extend, closed_upgrade_freef];
    (* TODO: why do we need these cases explicitly now? *)
    try solve [eapply stp2_sela1; eauto];
    try solve [eapply stp2_sela2; eauto];
    try solve [eapply stp2_selax; eauto];
    try solve [eapply stp2_transf; eauto].
Qed.

Lemma stp2_extend2 : forall v1 G1 G2 T1 T2 H s m n,
                       stp2 s m G1 T1 G2 T2 H n ->
                       stp2 s m G1 T1 (v1::G2) T2 H n.
Proof.
  intros. apply (proj2 (stp2_extend v1 G1 G2 T1 T2 H s m n H0)).
Qed.

Lemma stp2_extend1 : forall v1 G1 G2 T1 T2 H s m n,
                       stp2 s m G1 T1 G2 T2 H n ->
                       stp2 s m (v1::G1) T1 G2 T2 H n.
Proof.
  intros. apply (proj1 (stp2_extend v1 G1 G2 T1 T2 H s m n H0)).
Qed.

Lemma stp2_extendH : forall v1 G1 G2 T1 T2 GH s m n,
                       stp2 s m G1 T1 G2 T2 GH n ->
                       stp2 s m G1 T1 G2 T2 (v1::GH) n.
Proof.
  intros.
  induction H;
    try solve [try constructor; simpl; eauto using index_extend, closed_upgrade_free];
    try solve [eapply stp2_transf; simpl; eauto].
  solve [eapply stp2_selxr; simpl; eauto using tm_closed_upgrade_free].
  assert (splice (length GH) T2 = T2) as A2. {
    eapply closed_splice_idem. apply H1. omega.
  }
  assert (splice (length GH) T4 = T4) as A4. {
    eapply closed_splice_idem. apply H2. omega.
  }
  assert (closed 0 (length GH) (length G2) T3). eapply stp2_closed1. eauto.
  assert (splice (length GH) T3 = T3) as A3. {
    eapply closed_splice_idem. eauto. omega.
  }
  assert (map (spliceat (length GH)) [(G2, T3)] ++ v1::GH =
          ((G2, T3)::v1::GH)) as HGX3. {
    simpl. rewrite A3. eauto.
  }
  eapply stp2_all.
  apply IHstp2_1.
  reflexivity.
  apply closed_inc. apply H1.
  apply closed_inc. apply H2.
  simpl.
  rewrite <- A2. rewrite <- A4.
  unfold open.
  change (varH (S (length GH))) with (varH (0 + (S (length GH)))).
  repeat rewrite -> (proj1 (splice_open_permute GH)).
  rewrite <- HGX3.
  apply stp2_splice.
  subst x. simpl. unfold open in H3. apply H3.
Qed.

Lemma stp2_extendH_mult : forall G1 G2 T1 T2 H H2 s m n,
                       stp2 s m G1 T1 G2 T2 H n ->
                       stp2 s m G1 T1 G2 T2 (H2++H) n.
Proof.
  intros. induction H2.
  - simpl. assumption.
  - simpl.
    apply stp2_extendH. assumption.
Qed.

Lemma stp2_extendH_mult0 : forall G1 G2 T1 T2 H2 s m n,
                       stp2 s m G1 T1 G2 T2 [] n ->
                       stp2 s m G1 T1 G2 T2 H2 n.
Proof.
  intros.
  assert (H2 = H2++[]) as A by apply app_nil_end. rewrite A.
  apply stp2_extendH_mult. assumption.
Qed.

Lemma stp2_reg  : forall G1 G2 T1 T2 GH s m n,
                    stp2 s m G1 T1 G2 T2 GH n ->
                    stpd2 s true G1 T1 G1 T1 GH /\ stpd2 s true G2 T2 G2 T2 GH.
Proof.
  intros.
  apply stp2_closed in H. destruct H as [H1 H2].
  split; apply stp2_refl; assumption.
Qed.

Lemma stp2_reg2 : forall G1 G2 T1 T2 GH s m n,
                       stp2 s m G1 T1 G2 T2 GH n ->
                       stpd2 s true G2 T2 G2 T2 GH.
Proof.
  intros. apply (proj2 (stp2_reg G1 G2 T1 T2 GH s m n H)).
Qed.

Lemma stp2_reg1 : forall G1 G2 T1 T2 GH s m n,
                       stp2 s m G1 T1 G2 T2 GH n ->
                       stpd2 s true G1 T1 G1 T1 GH.
Proof.
  intros. apply (proj1 (stp2_reg G1 G2 T1 T2 GH s m n H)).
Qed.

Lemma stp_reg  : forall G GH T1 T2,
                    stp G GH T1 T2 ->
                    stp G GH T1 T1 /\ stp G GH T2 T2.
Proof.
  intros.
  apply stp_closed in H. destruct H as [H1 H2].
  split; apply stp_refl; assumption.
Qed.

Lemma stp_reg2 : forall G GH T1 T2,
                       stp G GH T1 T2 ->
                       stp G GH T2 T2.
Proof.
  intros. apply (proj2 (stp_reg G GH T1 T2 H)).
Qed.

Lemma stp_reg1 : forall G GH T1 T2,
                       stp G GH T1 T2 ->
                       stp G GH T1 T1.
Proof.
  intros. apply (proj1 (stp_reg G GH T1 T2 H)).
Qed.

Lemma stpd2_extend2 : forall v1 G1 G2 T1 T2 H s m,
                       stpd2 s m G1 T1 G2 T2 H ->
                       stpd2 s m G1 T1 (v1::G2) T2 H.
Proof.
  intros. destruct H0 as [n Hsub]. eexists n.
  apply stp2_extend2; eauto.
Qed.

Lemma stpd2_extend1 : forall v1 G1 G2 T1 T2 H s m,
                       stpd2 s m G1 T1 G2 T2 H ->
                       stpd2 s m (v1::G1) T1 G2 T2 H.
Proof.
  intros. destruct H0 as [n Hsub]. eexists n.
  apply stp2_extend1; eauto.
Qed.

Lemma stpd2_extendH : forall v1 G1 G2 T1 T2 GH s m,
                       stpd2 s m G1 T1 G2 T2 GH ->
                       stpd2 s m G1 T1 G2 T2 (v1::GH).
Proof.
  intros. destruct H as [n Hsub]. exists n.
  apply stp2_extendH; eauto.
Qed.

Lemma stpd2_extendH_mult : forall G1 G2 T1 T2 GH GH2 s m,
                       stpd2 s m G1 T1 G2 T2 GH ->
                       stpd2 s m G1 T1 G2 T2 (GH2++GH).
Proof.
  intros. destruct H as [n Hsub]. exists n.
  apply stp2_extendH_mult; eauto.
Qed.

Lemma stpd2_closed2 : forall G1 G2 T1 T2 GH s m,
                       stpd2 s m G1 T1 G2 T2 GH ->
                       closed 0 (length GH) (length G2) T2.
Proof.
  intros. destruct H as [n Hsub].
  eapply stp2_closed2; eauto.
Qed.

Lemma stpd2_closed1 : forall G1 G2 T1 T2 GH s m,
                       stpd2 s m G1 T1 G2 T2 GH ->
                       closed 0 (length GH) (length G1) T1.
Proof.
  intros. destruct H as [n Hsub].
  eapply stp2_closed1; eauto.
Qed.

Lemma valtp_extend : forall vs v v1 T,
                       val_type vs v T ->
                       val_type (v1::vs) v T.
Proof.
  intros. induction H; eauto; econstructor; eauto; eapply stpd2_extend2; eauto.
Qed.

Lemma index_safe_ex: forall H1 G1 TF i,
             wf_env H1 G1 ->
             index i G1 = Some TF ->
             exists v, index i H1 = Some v /\ val_type H1 v TF.
Proof. intros. induction H.
   - Case "nil". inversion H0.
   - Case "cons". inversion H0.
     case_eq (beq_nat i (length ts)); intros E2.
     * SSCase "hit".
       rewrite E2 in H3. inversion H3. subst. clear H3.
       assert (length ts = length vs). symmetry. eapply wf_length. eauto.
       simpl. rewrite H2 in E2. rewrite E2.
       eexists. split. eauto. assumption.
     * SSCase "miss".
       rewrite E2 in H3.
       assert (exists v0,
                 index i vs = Some v0 /\ val_type vs v0 TF). eauto.
       destruct H2. destruct H2.
       eexists. split. eapply index_extend. eauto.
       eapply valtp_extend. assumption.
Qed.

Lemma index_safeh_ex: forall H1 H2 G1 GH TF i,
             wf_env H1 G1 -> wf_envh H1 H2 GH ->
             index i GH = Some TF ->
             exists v, index i H2 = Some v /\ valh_type H1 H2 v TF.
Proof. intros. induction H0.
   - Case "nil". inversion H3.
   - Case "cons". inversion H3.
     case_eq (beq_nat i (length ts)); intros E2.
     * SSCase "hit".
       rewrite E2 in H2. inversion H2. subst. clear H2.
       assert (length ts = length vs). symmetry. eapply wfh_length. eauto.
       simpl. rewrite H1 in E2. rewrite E2.
       eexists. split. eauto. econstructor.
     * SSCase "miss".
       rewrite E2 in H2.
       assert (exists v : venv * ty,
                 index i vs = Some v /\ valh_type vvs vs v TF). eauto.
       destruct H1. destruct H1.
       eexists. split. eapply index_extend. eauto.
       inversion H4. subst.
       eapply v_tya. (* aenv is not constrained -- bit of a cheat?*)
Qed.

Inductive res_type: venv -> option vl -> ty -> Prop :=
| not_stuck: forall venv v T,
      val_type venv v T ->
      res_type venv (Some v) T.

Hint Constructors res_type.
Hint Resolve not_stuck.

(* ### Transitivity ### *)

Lemma stpd2_top: forall G1 G2 GH T s,
    closed 0 (length GH) (length G1) T ->
    stpd2 s true G1 T G2 TTop GH.
Proof. intros. exists (S 0). eauto. Qed.
Lemma stpd2_bot: forall G1 G2 GH T s,
    closed 0 (length GH) (length G2) T ->
    stpd2 s true G1 TBot G2 T GH.
Proof. intros. exists (S 0). eauto. Qed.
Lemma stpd2_mem: forall G1 G2 S1 U1 S2 U2 GH s,
    stpd2 s s G1 U1 G2 U2 GH ->
    stpd2 s false G2 S2 G1 S1 GH ->
    stpd2 s true G1 (TMem S1 U1) G2 (TMem S2 U2) GH.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_strong_sel1: forall G1 G2 GX TX t T2 GH,
    peval G1 t (vty GX TX) ->
    val_type GX (vty GX TX) (TMem TX TX) -> (* for downgrade *)
    closed 0 0 (length GX) TX ->
    stpd2 true true GX TX G2 T2 GH ->
    stpd2 true true G1 (TSel t) G2 T2 GH.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_strong_sel2: forall G1 G2 GX TX t T1 GH,
    peval G2 t (vty GX TX) ->
    val_type GX (vty GX TX) (TMem TX TX) -> (* for downgrade *)
    closed 0 0 (length GX) TX ->
    stpd2 true false G1 T1 GX TX GH ->
    stpd2 true true G1 T1 G2 (TSel t) GH.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_sel1: forall G1 G2 v TX t T2 GH,
    peval G1 t v ->
    val_type (base v) v TX ->
    closed 0 0 (length (base v)) TX ->
    stpd2 false false (base v) TX G2 (TMem TBot T2) GH ->
    stpd2 false true G1 (TSel t) G2 T2 GH.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_sel2: forall G1 G2 v TX t T1 GH,
    peval G2 t v ->
    val_type (base v) v TX ->
    closed 0 0 (length (base v)) TX ->
    stpd2 false false (base v) TX G1 (TMem T1 TTop) GH ->
    stpd2 false true G1 T1 G2 (TSel t) GH.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_selxr: forall G1 G2 G t GH s,
    join_env G1 G2 G ->
    tm_closed 0 (length GH) (length G) t ->
    stpd2 s true G1 (TSel t) G2 (TSel t) GH.
Proof. intros. exists (S 0). eauto. Qed.
Lemma stpd2_selx: forall G1 G2 v t1 t2 GH s,
    peval G1 t1 v ->
    peval G2 t2 v ->
    stpd2 s true G1 (TSel t1) G2 (TSel t2) GH.
Proof. intros. exists (S 0). eauto. Qed.
Lemma stpd2_sela1: forall G1 G2 GX TX x T2 GH,
    index x GH = Some (GX, TX) ->
    closed 0 x (length GX) TX ->
    stpd2 false false GX TX G2 (TMem TBot T2) GH ->
    stpd2 false true G1 (TSel (tvar (varH x))) G2 T2 GH.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_sela2: forall G1 G2 GX T1 TX x GH,
    index x GH = Some (GX, TX) ->
    closed 0 x (length GX) TX ->
    stpd2 false false GX TX G1 (TMem T1 TTop) GH ->
    stpd2 false true G1 T1 G2 (TSel (tvar (varH x))) GH.
Proof. intros. repeat eu. eauto. Qed.
(*
Lemma stpd2_selax: forall G1 G2 v x GH s,
    index x GH = Some v ->
    stpd2 s true G1 (TSel (tvar (varH x))) G2 (TSel (tvar (varH x))) GH.
Proof. intros. exists (S 0). eauto. Qed.
*)
Lemma stpd2_all: forall G1 G2 T1 T2 T3 T4 x GH s,
    stpd2 false false G2 T3 G1 T1 GH ->
    x = length GH ->
    closed 1 (length GH) (length G1) T2 ->
    closed 1 (length GH) (length G2) T4 ->
    stpd2 false false G1 (open (tvar (varH x)) T2) G2 (open (tvar (varH x)) T4) ((G2, T3)::GH) ->
    stpd2 s true G1 (TAll T1 T2) G2 (TAll T3 T4) GH.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_wrapf: forall G1 G2 T1 T2 GH s,
    stpd2 s true G1 T1 G2 T2 GH ->
    stpd2 s false G1 T1 G2 T2 GH.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_transf: forall G1 G2 G3 T1 T2 T3 GH s,
    stpd2 s true G1 T1 G2 T2 GH ->
    stpd2 s false G2 T2 G3 T3 GH ->
    stpd2 s false G1 T1 G3 T3 GH.
Proof. intros. repeat eu. eauto. Qed.

Lemma stpd2_trans_aux: forall n, forall G1 G2 G3 T1 T2 T3 H s n1,
  stp2 s false G1 T1 G2 T2 H n1 -> n1 < n ->
  stpd2 s false G2 T2 G3 T3 H ->
  stpd2 s false G1 T1 G3 T3 H.
Proof.
  intros n. induction n; intros; try omega; repeat eu; subst; inversion H0.
  - Case "wrapf". eapply stpd2_transf; eauto.
  - Case "transf". eapply stpd2_transf. eauto. eapply IHn. eauto. omega. eauto.
Qed.

Lemma stpd2_trans: forall G1 G2 G3 T1 T2 T3 H s,
  stpd2 s false G1 T1 G2 T2 H ->
  stpd2 s false G2 T2 G3 T3 H ->
  stpd2 s false G1 T1 G3 T3 H.
Proof. intros. repeat eu. eapply stpd2_trans_aux; eauto. Qed.

Lemma stp2_narrow_aux: forall n, forall m G1 T1 G2 T2 GH n0,
  stp2 false m G1 T1 G2 T2 GH n0 ->
  n0 <= n ->
  forall GH1 GH0 GH' GX1 TX1 GX2 TX2,
    GH=GH1++[(GX2,TX2)]++GH0 ->
    GH'=GH1++[(GX1,TX1)]++GH0 ->
    stpd2 false false GX1 TX1 GX2 TX2 GH0 ->
    stpd2 false m G1 T1 G2 T2 GH'.
Proof.
  intros n.
  induction n.
  - Case "z". intros. inversion H0. subst. inversion H; eauto.
  - Case "s n". intros m G1 T1 G2 T2 GH n0 H NE. inversion H; subst;
    intros GH1 GH0 GH' GX1 TX1 GX2 TX2 EGH EGH' HX; eauto.
    + SCase "top". eapply stpd2_top.
      subst. rewrite app_length. simpl. rewrite app_length in H0. simpl in H0. apply H0.
    + SCase "bot". eapply stpd2_bot.
      subst. rewrite app_length. simpl. rewrite app_length in H0. simpl in H0. apply H0.
    + SCase "mem_true". eapply stpd2_mem.
      eapply IHn; try eassumption. omega.
      eapply IHn; try eassumption. omega.
    + SCase "sel1". eapply stpd2_sel1; try eassumption.
      eapply IHn; try eassumption. omega.
    + SCase "sel2". eapply stpd2_sel2; try eassumption.
      eapply IHn; try eassumption. omega.
    + SCase "selxr". eapply stpd2_selxr. eassumption.
      subst. rewrite app_length. simpl. rewrite app_length in H1. simpl in H1. apply H1.
    + SCase "sela1".
      unfold id,venv,aenv in *.
      case_eq (beq_nat x (length GH0)); intros E.
      * assert (index x ([(GX2, TX2)]++GH0) = Some (GX2, TX2)) as A2. {
          simpl. rewrite E. reflexivity.
        }
        assert (index x GH = Some (GX2, TX2)) as A2'. {
          rewrite EGH. eapply index_extend_mult. apply A2.
        }
        unfold venv in A2'. rewrite A2' in H0. inversion H0. subst.
        inversion HX as [nx HX'].
        eapply stpd2_sela1.
        eapply index_extend_mult. simpl. rewrite E. reflexivity.
        apply beq_nat_true in E. rewrite E. eapply stp2_closed1. eassumption.
        eapply stpd2_trans.
        eexists. eapply stp2_extendH_mult. eapply stp2_extendH_mult. eassumption.
        eapply IHn; try eassumption. omega.
        reflexivity. reflexivity.
      * assert (index x GH' = Some (GX, TX)) as A. {
          subst.
          eapply index_same. apply E. eassumption.
        }
        eapply stpd2_sela1. eapply A. assumption.
        eapply IHn; try eassumption. omega.
    + SCase "sela2".
      unfold id,venv,aenv in *.
      case_eq (beq_nat x (length GH0)); intros E.
      * assert (index x ([(GX2, TX2)]++GH0) = Some (GX2, TX2)) as A2. {
          simpl. rewrite E. reflexivity.
        }
        assert (index x GH = Some (GX2, TX2)) as A2'. {
          rewrite EGH. eapply index_extend_mult. apply A2.
        }
        unfold venv in A2'. rewrite A2' in H0. inversion H0. subst.
        inversion HX as [nx HX'].
        eapply stpd2_sela2.
        eapply index_extend_mult. simpl. rewrite E. reflexivity.
        apply beq_nat_true in E. rewrite E. eapply stp2_closed1. eassumption.
        eapply stpd2_trans.
        eexists. eapply stp2_extendH_mult. eapply stp2_extendH_mult. eassumption.
        eapply IHn; try eassumption. omega.
        reflexivity. reflexivity.
      * assert (index x GH' = Some (GX, TX)) as A. {
          subst.
          eapply index_same. apply E. eassumption.
        }
        eapply stpd2_sela2. eapply A. assumption.
        eapply IHn; try eassumption. omega.
(*
    + SCase "selax".
      unfold id,venv,aenv in *.
      case_eq (beq_nat x (length GH0)); intros E.
      * assert (index x ([(GX2, TX2)]++GH0) = Some (GX2, TX2)) as A2. {
          simpl. rewrite E. reflexivity.
        }
        assert (index x GH = Some (GX2, TX2)) as A2'. {
          rewrite EGH. eapply index_extend_mult. apply A2.
        }
        unfold venv in A2'. rewrite A2' in H0. inversion H0. subst.
        inversion HX as [nx HX'].
        eapply stpd2_selax.
        eapply index_extend_mult. simpl. unfold id,venv,aenv in *. rewrite E.
        reflexivity.
      * assert (index x GH' = Some v) as A. {
          subst.
          eapply index_same. apply E. eassumption.
        }
        eapply stpd2_selax. eapply A.
*)
    + SCase "all".
      assert (length GH = length GH') as A. {
        subst. clear.
        induction GH1.
        - simpl. reflexivity.
        - simpl. simpl in IHGH1. rewrite IHGH1. reflexivity.
      }
      eapply stpd2_all.
      eapply IHn; try eassumption. omega.
      rewrite <- A. reflexivity.
      rewrite <- A. assumption. rewrite <- A. assumption.
      subst.
      eapply IHn with (GH1:=(G2, T4) :: GH1); try eassumption. omega.
      simpl. reflexivity. simpl. reflexivity.
    + SCase "wrapf".
      eapply stpd2_wrapf.
      eapply IHn; try eassumption. omega.
    + SCase "transf".
      eapply stpd2_transf.
      eapply IHn; try eassumption. omega.
      eapply IHn; try eassumption. omega.
Grab Existential Variables. apply 0.
Qed.

Lemma stpd2_narrow: forall G1 G2 G3 G4 T1 T2 T3 T4 H,
  stpd2 false false G1 T1 G2 T2 H -> (* careful about H! *)
  stpd2 false false G3 T3 G4 T4 ((G2,T2)::H) ->
  stpd2 false false G3 T3 G4 T4 ((G1,T1)::H).
Proof.
  intros. inversion H1 as [n H'].
  eapply (stp2_narrow_aux n) with (GH1:=[]) (GH0:=H). eapply H'. omega.
  simpl. reflexivity. reflexivity.
  assumption.
Qed.

Ltac index_contra :=
  match goal with
    | H: index ?N [] = Some ?V |- _ => simpl in H; inversion H
  end.

Ltac peval_contra :=
  match goal with
    | H: peval _ (tvar (varH _)) _ |- _ =>
      destruct H as [? [_n _Ev]]; destruct _n; simpl in _Ev; solve [inversion _Ev]
  end.

Lemma symmetry_join_env: forall {X:Type} (G1: list X) G2 G,
  join_env G1 G2 G ->
  join_env G2 G1 G.
Proof.
  intros. unfold join_env in *. destruct H as [G1' [G2' [Eq1 Eq2]]].
  exists G2'. exists G1'. eauto.
Qed.

Lemma tm_closed_join_env: forall {X:Type} (G1: list X) G2 G t i j,
  join_env G1 G2 G ->
  tm_closed 0 0 (length G1) t ->
  tm_closed i j (length G) t ->
  tm_closed 0 0 (length G2) t.
Proof.
  admit.
Qed.

Lemma peval_join_env: forall G1 G2 G t v i j,
  join_env G1 G2 G ->
  tm_closed i j (length G) t ->
  peval G1 t v ->
  tm_closed 0 0 (length G2) t /\ peval G2 t v.
Proof.
  admit.
Qed.

Lemma stpd2_untrans_aux: forall n, forall m G1 G2 G3 T1 T2 T3 GH n1,
  stp2 true m G1 T1 G2 T2 GH n1 -> n1 < n ->
  stpd2 true true G2 T2 G3 T3 GH ->
  stpd2 true true G1 T1 G3 T3 GH.
Proof.
  intros n. induction n; intros; try omega. eu.
  inversion H; subst;
  try solve [inversion H1; eexists; eauto];
  try solve [eapply stpd2_bot; eauto using stp2_closed2];
  try solve [eapply stpd2_strong_sel1; eauto; eapply IHn; eauto; try omega];
  try solve [eapply IHn; [eapply H2 | omega | eauto]]; (* wrapf *)
  try solve [eapply IHn; [eapply H2 | omega | (eapply IHn; [ eapply H3 | omega | eauto ])]]; (* transf *)
  inversion H1; subst;
  try solve [eapply stpd2_top; eauto using stp2_closed1];
  try solve [eapply stpd2_strong_sel2; eauto];
  try solve [eapply stpd2_mem; [eapply IHn; eauto; try omega |
                                eapply stpd2_trans; eauto]];
  try solve [eapply stpd2_sela1; eauto; eapply stpd2_wrapf; eapply IHn; eauto; try omega];
  try solve [index_contra];
  try solve [peval_contra].
  - Case "sel2 - sel1".
    assert (vty GX TX = vty GX0 TX0) as Eqv by solve [eapply peval_unique; eauto].
    inversion Eqv. subst.
    eapply IHn. eauto. omega. eauto.
  - Case "sel2 - selxr".
    eapply stpd2_strong_sel2; eauto.
    eapply peval_join_env; eauto.
  - Case "sel2 - selx".
    assert (vty GX TX = v) as Eqv by solve [eapply peval_unique; eauto]. subst.
    eapply stpd2_strong_sel2; eauto.
  - Case "selxr - sel1".
    eapply stpd2_strong_sel1; eauto.
    eapply peval_join_env; eauto using symmetry_join_env.
  - Case "selxr - selxr".
    admit.
  - Case "selxr - selx".
    eapply stpd2_selx; eauto.
    eapply peval_join_env; eauto using symmetry_join_env.
  - Case "selx - sel1".
    assert (vty GX TX = v) as Eqv by solve [eapply peval_unique; eauto]. subst.
    eapply stpd2_strong_sel1; eauto.
  - Case "selx - selxr".
    eapply stpd2_selx; eauto.
    eapply peval_join_env; eauto.
  - Case "selx - selx".
    assert (v = v0) as Eqv by solve [eapply peval_unique; eauto]. subst.
    eapply stpd2_selx; eauto.
  - Case "all - all".
    eapply stpd2_all; eauto.
    eapply stpd2_trans; eauto.
    eapply stpd2_trans. eapply stpd2_narrow. eexists. eapply H8. eauto. eauto.
Grab Existential Variables. apply 0.
Qed.

(* We don't generally need to push back transitivity in non-empty abstract contexts. *)
Lemma stpd2_strong_trans: forall G1 G2 G3 T1 T2 T3,
  stpd2 true true G1 T1 G2 T2 [] ->
  stpd2 true true G2 T2 G3 T3 [] ->
  stpd2 true true G1 T1 G3 T3 [].
Proof. intros. repeat eu. eapply stpd2_untrans_aux; eauto. Qed.

Lemma stpd2_strong_untrans: forall G1 G2 T1 T2,
  stpd2 true false G1 T1 G2 T2 [] ->
  stpd2 true true G1 T1 G2 T2 [].
Proof.
  intros. destruct H as [n H].
  eapply stpd2_untrans_aux; eauto using stp2_reg2.
Qed.

Lemma valtp_widen: forall vf H1 H2 T1 T2,
  val_type H1 vf T1 ->
  stpd2 true true H1 T1 H2 T2 [] ->
  val_type H2 vf T2.
Proof.
  intros. inversion H; subst; econstructor; eauto; eapply stpd2_strong_trans; eauto.
Qed.

Lemma restp_widen: forall vf H1 H2 T1 T2,
  res_type H1 vf T1 ->
  stpd2 true true H1 T1 H2 T2 [] ->
  res_type H2 vf T2.
Proof.
  intros. inversion H. eapply not_stuck. eapply valtp_widen; eauto.
Qed.

Lemma invert_typ: forall venv vx S U,
  val_type venv vx (TMem S U) ->
  exists GX TX,
    vx = (vty GX TX) /\
    stpd2 true false venv S GX TX [] /\
    stpd2 true true GX TX venv U [].
Proof.
  intros. inversion H; ev; try solve by inversion; inversion H1; subst;
  repeat eexists; eauto.
Qed.

Lemma stpd2_to_strong_aux: forall n, forall G1 G2 T1 T2 m n1,
  stp2 false m G1 T1 G2 T2 [] n1 -> n1 < n ->
  stpd2 true m G1 T1 G2 T2 [].
Proof.
  intros n. induction n; intros; try omega.
  inversion H; subst; try solve [inversion H1].
  - Case "top".
    eapply stpd2_top; eauto.
  - Case "bot".
    eapply stpd2_bot; eauto.
  - Case "mem".
    eapply stpd2_mem; auto.
    eapply stpd2_strong_untrans. eapply IHn; eauto. omega.
    eapply IHn; eauto. omega.
  - Case "sel1".
    eapply IHn in H4. eapply stpd2_strong_untrans in H4.
    eapply valtp_widen with (2:=H4) in H2.
    remember H2 as Hv. clear HeqHv.
    eapply invert_typ in H2. ev. subst.
    assert (closed 0 (length ([]:aenv)) (length x) x0). eapply stpd2_closed1; eauto.
    eapply stpd2_strong_sel1. eauto.
    inversion Hv; subst.
    eapply v_ty. eassumption. eapply stp2_refl. eauto. eauto.
    eassumption. omega.
  - Case "sel2".
    eapply IHn in H4. eapply stpd2_strong_untrans in H4.
    eapply valtp_widen with (2:=H4) in H2.
    remember H2 as Hv. clear HeqHv.
    eapply invert_typ in H2. ev. subst.
    assert (closed 0 (length ([]:aenv)) (length x) x0). eapply stpd2_closed1; eauto.
    eapply stpd2_strong_sel2. eauto.
    inversion Hv; subst.
    eapply v_ty. eassumption. eapply stp2_refl. eauto. eauto.
    eassumption. omega.
  - Case "selxr".
    eapply stpd2_selxr; eauto.
  - Case "selx".
    eapply stpd2_selx; eauto.
  - Case "all".
    eapply stpd2_all; eauto.
  - Case "wrapf".
    eapply stpd2_wrapf; eauto.
    eapply IHn; eauto. omega.
  - Case "transf".
    eapply stpd2_transf.
    eapply IHn; eauto. omega.
    eapply IHn; eauto. omega.
Qed.

Lemma stpd2_to_strong: forall G1 G2 T1 T2 m,
  stpd2 false m G1 T1 G2 T2 [] ->
  stpd2 true m G1 T1 G2 T2 [].
Proof. intros. repeat eu. eapply stpd2_to_strong_aux; eauto. Qed.

Lemma stpd2_upgrade: forall G1 G2 T1 T2,
  stpd2 false false G1 T1 G2 T2 nil ->
  stpd2 true true G1 T1 G2 T2 nil.
Proof.
  intros.
  eapply stpd2_strong_untrans. eapply stpd2_to_strong. eauto.
Qed.

Lemma stpd2_downgrade_aux: forall G1 G2 T1 T2 H m,
  stpd2 true m G1 T1 G2 T2 H ->
  stpd2 false m G1 T1 G2 T2 H.
Proof.
  intros. inversion H0. dependent induction H1; try solve [eexists; eauto].
  - Case "mem".
    eapply stpd2_mem. eapply stpd2_wrapf. eapply IHstp2_1. eexists. eassumption.
    eapply IHstp2_2. eexists. eassumption.
  - Case "sel1".
    eapply stpd2_sel1; eauto. simpl.
    eapply stpd2_wrapf. eapply stpd2_mem.
    eapply stpd2_wrapf. eapply IHstp2. eexists. eassumption.
    eapply stpd2_wrapf. eapply stpd2_bot.
    eapply closed_upgrade_free. eassumption. omega.
  - Case "sel2".
    eapply stpd2_sel2; eauto. simpl.
    eapply stpd2_wrapf. eapply stpd2_mem.
    eapply stpd2_wrapf. eapply stpd2_top.
    simpl. eapply closed_upgrade_free. eassumption. omega.
    eapply IHstp2. eexists. eassumption.
  - Case "wrap".
    eapply stpd2_wrapf. eapply IHstp2. eexists. eassumption.
  - Case "trans".
    eapply stpd2_transf.
    eapply IHstp2_1. eexists. eassumption.
    eapply IHstp2_2. eexists. eassumption.
  Grab Existential Variables.
  apply 0. apply 0. apply 0. apply 0.
Qed.

Lemma stpd2_downgrade: forall G1 G2 T1 T2 H,
  stpd2 true true G1 T1 G2 T2 H ->
  stpd2 false false G1 T1 G2 T2 H.
Proof.
  intros. eapply stpd2_downgrade_aux. eapply stpd2_wrapf. assumption.
Qed.

(* ### Substitution for relating static and dynamic semantics ### *)
Lemma index_hit2 {X}: forall x (B:X) A G,
  length G = x ->
  B = A ->
  index x (B::G) = Some A.
Proof.
  intros.
  unfold index.
  assert (beq_nat x (length G) = true). eapply beq_nat_true_iff. eauto.
  rewrite H1. subst. reflexivity.
Qed.

Lemma index_miss {X}: forall x (B:X) A G,
  index x (B::G) = A ->
  x <> (length G)  ->
  index x G = A.
Proof.
  intros.
  unfold index in H.
  assert (beq_nat x (length G) = false). eapply beq_nat_false_iff. eauto.
  rewrite H1 in H. eauto.
Qed.

Lemma index_hit {X}: forall x (B:X) A G,
  index x (B::G) = Some A ->
  x = length G ->
  B = A.
Proof.
  intros.
  unfold index in H.
  assert (beq_nat x (length G) = true). eapply beq_nat_true_iff. eauto.
  rewrite H1 in H. inversion H. eauto.
Qed.

Lemma index_hit0: forall GH (GX0:venv) (TX0:ty),
      index 0 (GH ++ [(GX0, TX0)]) =
      Some (GX0, TX0).
Proof.
  intros GH. induction GH.
  - intros. simpl. eauto.
  - intros. simpl. destruct a. simpl. rewrite app_length. simpl.
    assert (length GH + 1 = S (length GH)). omega. rewrite H.
    eauto.
Qed.

Hint Resolve beq_nat_true_iff.
Hint Resolve beq_nat_false_iff.

Lemma closed_no_open:
  (forall T x i j k,
   closed i j k T ->
   T = open_rec i x T) /\
  (forall t x i j k,
   tm_closed i j k t ->
   t = tm_open_rec i x t).
Proof.
  apply tytm_mutind; intros; simpl;
  try (inversion H; inversion H4; subst);
  try (inversion H1; subst);
  try (inversion H0; subst);
  try (erewrite <- H; eauto);
  try (erewrite <- H0; eauto);
  eauto.
  case_eq (beq_nat i x0); intros E; eauto.
  apply beq_nat_true in E. subst. omega.
Qed.

Lemma open_subst_commute:
(forall T2 V j k x i,
tm_closed i j k V ->
(open_rec i (tvar (varH x)) (subst V T2)) =
(subst V (open_rec i (tvar (varH (x+1))) T2))) /\
(forall t2 V j k x i,
tm_closed i j k V ->
(tm_open_rec i (tvar (varH x)) (tm_subst V t2)) =
(tm_subst V (tm_open_rec i (tvar (varH (x+1))) t2))).
Proof.
  apply tytm_mutind; intros; eauto; simpl;
  try (erewrite H; eauto); try (erewrite H0; eauto);
  eauto using tm_closed_upgrade.
  destruct v; eauto; simpl.

  - case_eq (beq_nat i0 0); intros E; eauto.
    erewrite (proj2 closed_no_open); eauto.

  - case_eq (beq_nat i i0); intros E; eauto. simpl.
    rewrite false_beq_nat. f_equal. f_equal.
    unfold id in *. omega. omega.
Qed.

Lemma closed_no_subst:
  (forall T i k TX,
   closed i 0 k T ->
   subst TX T = T) /\
  (forall t i k TX,
   tm_closed i 0 k t ->
   tm_subst TX t = t).
Proof.
  apply tytm_mutind; intros; simpl;
  try (inversion H; inversion H4; subst);
  try (inversion H1; subst);
  try (inversion H0; subst);
  try (erewrite H; eauto);
  try (erewrite H0; eauto);
  eauto; try omega.
Qed.

Lemma closed_subst:
  (forall T i j k V, closed i (j+1) k T -> tm_closed 0 j k V -> closed i j k (subst V T)) /\
  (forall t i j k V, tm_closed i (j+1) k t -> tm_closed 0 j k V -> tm_closed i j k (tm_subst V t)).
Proof.
  apply tytm_mutind; intros; eauto; simpl; try solve [
  try inversion H1; try inversion H0; subst;
  try econstructor;
  try eapply H; eauto; try eapply H0; eauto;
  eauto using tm_closed_upgrade_freef].

  - inversion H; subst; inversion H5; subst; eauto.
    case_eq (beq_nat x 0); intros E;
    [ eapply beq_nat_true in E | eapply beq_nat_false in E];
    subst.
    + eapply (proj2 closed_inc_mult); eauto. omega.
    + econstructor. econstructor. omega.
Qed.

Lemma closed_nosubst:
  (forall T i j k V, closed i (j+1) k T -> nosubst T -> closed i j k (subst V T)) /\
  (forall t i j k V, tm_closed i (j+1) k t -> tm_nosubst t -> tm_closed i j k (tm_subst V t)).
Proof.
  apply tytm_mutind; intros; eauto;
  try inversion H; try inversion H0; try inversion H1; try inversion H2; subst;
  try econstructor;
  try eapply H; eauto; try eapply H0; eauto.

  - inversion H5; subst;
    simpl; try solve [econstructor; econstructor; omega].
    simpl in H0.
    rewrite false_beq_nat. econstructor. econstructor.
    unfold id in *. omega.
    unfold id in *. omega.
Qed.

Lemma subst_open_commute_m:
  (forall T2 i j k k' j' V, closed (i+1) (j+1) k T2 -> tm_closed 0 j' k' V ->
   subst V (open_rec i (tvar (varH (j+1))) T2) = open_rec i (tvar (varH j)) (subst V T2)) /\
  (forall t2 i j k k' j' V, tm_closed (i+1) (j+1) k t2 -> tm_closed 0 j' k' V ->
   tm_subst V (tm_open_rec i (tvar (varH (j+1))) t2) = tm_open_rec i (tvar (varH j)) (tm_subst V t2)).
Proof.
  apply tytm_mutind; intros; eauto; simpl; try solve [
  try inversion H1; try inversion H0; subst;
  try econstructor;
  try erewrite H; eauto; try erewrite H0; eauto].
  inversion H; subst. inversion H5; subst; eauto; simpl.
  - case_eq (beq_nat x 0); intros E; eauto; simpl.
    eapply beq_nat_true in E. subst.
    erewrite <- (proj2 closed_no_open); eauto.
    eapply tm_closed_upgrade; eauto. omega.
  - case_eq (beq_nat i x); intros E; eauto; simpl.
    eapply beq_nat_true in E. subst.
    case_eq (beq_nat (j+1) 0); intros E1; eauto; simpl.
    eapply beq_nat_true in E1. subst. omega.
    eapply beq_nat_false in E1. f_equal. f_equal. omega.
Qed.

Lemma subst_open_commute: forall i j k k' V T2, closed (i+1) (j+1) k T2 -> tm_closed 0 0 k' V ->
    subst V (open_rec i (tvar (varH (j+1))) T2) = open_rec i (tvar (varH j)) (subst V T2).
Proof.
  intros. eapply subst_open_commute_m; eauto.
Qed.

Lemma subst_open_zero:
  (forall T2 i i' k TX, closed i' 0 k T2 ->
   subst TX (open_rec i (tvar (varH 0)) T2) = open_rec i TX T2) /\
  (forall t2 i i' k TX, tm_closed i' 0 k t2 ->
   tm_subst TX (tm_open_rec i (tvar (varH 0)) t2) = tm_open_rec i TX t2).
Proof.
  apply tytm_mutind; intros; simpl; eauto;
  try inversion H1; try inversion H0; subst;
  repeat erewrite H; eauto; repeat erewrite H0; eauto.
  inversion H; subst. inversion H4; subst; eauto; simpl.
  case_eq (beq_nat x 0); intros E; omega.
  case_eq (beq_nat i x); intros E; eauto.
Qed.

Lemma Forall2_length: forall A B f (G1:list A) (G2:list B),
                        Forall2 f G1 G2 -> length G1 = length G2.
Proof.
  intros. induction H.
  eauto.
  simpl. eauto.
Qed.

Lemma nosubst_intro:
  (forall T i k, closed i 0 k T -> nosubst T) /\
  (forall t i k, tm_closed i 0 k t -> tm_nosubst t).
Proof.
  apply tytm_mutind; intros;
  try inversion H; try inversion H1; try inversion H0; try inversion H4; subst; simpl;
  eauto.
  omega.
Qed.

Lemma nosubst_open:
  (forall T2 i V, tm_nosubst V -> nosubst T2 -> nosubst (open_rec i V T2)) /\
  (forall t2 i V, tm_nosubst V -> tm_nosubst t2 -> tm_nosubst (tm_open_rec i V t2)).
Proof.
  apply tytm_mutind; intros;
  try inversion H2; try inversion H1; subst; simpl;
  eauto.
  simpl in H0. destruct v; simpl; eauto.
  case_eq (beq_nat i i0); intros E; eauto.
Qed.

(*
when and how we can replace with multiple environments:

stp2 G1 T1 G2 T2 (GH0 ++ [(vty GX TX)])

1) T1 closed

   stp2 G1 T1 G2' T2' (subst GH0)

2) G1 contains (GX TX) at some index x1

   index x1 G1 = (GX TX)
   stp2 G (subst (TVarF x1) T1) G2' T2'

3) G1 = GX

   stp2 G1 (subst TX T1) G2' T2'

4) G1 and GX unrelated

   stp2 ((GX,TX) :: G1) (subst (TVarF (length G1)) T1) G2' T2'

*)

(* ---- two-env substitution. first define what 'compatible' types mean. ---- *)

Definition compat (GX:venv) (TX: ty) (V: option vl) (G1:venv) (T1:ty) (T1':ty) :=
  (exists t1 v, peval G1 t1 v /\ V = Some v /\ GX = base v /\ val_type GX v TX /\ T1' = (subst t1 T1)) \/
  (closed 0 0 (length G1) T1 /\ T1' = T1) \/ (* this one is for convenience: redundant with next *)
  (nosubst T1 /\ T1' = subst (tvar (varF 0)) T1).


Definition compat2 (GX:venv) (TX: ty) (V: option vl) (p1:(venv*ty)) (p2:(venv*ty)) :=
  match p1, p2 with
      (G1,T1), (G2,T2) => G1 = G2 /\ compat GX TX V G1 T1 T2
  end.

Lemma closed_compat: forall GX TX V GXX TXX TXX' i j,
  compat GX TX V GXX TXX TXX' ->
  closed 0 j (length GXX) TX ->
  closed i (j+1) (length GXX) TXX ->
  closed i j (length GXX) TXX'.
Proof.
  intros. inversion H;[|destruct H2;[|destruct H2]].
  - destruct H2. destruct H2. destruct H2. destruct H3. destruct H4. destruct H4.
    destruct H5. rewrite H5.
    eapply closed_subst. eauto.
    eapply tm_closed_upgrade_free. eapply peval_closed. eauto. omega.
  - destruct H2. rewrite H3.
    eapply closed_upgrade. eapply closed_upgrade_free. eauto. omega. omega.
  - subst. eapply closed_nosubst. eauto. eauto.
Qed.

Lemma index_compat_miss0: forall GH GH' GX TX V (GXX:venv) (TXX:ty) n,
      Forall2 (compat2 GX TX V) GH GH' ->
      index (n+1) (GH ++ [(GX, TX)]) = Some (GXX,TXX) ->
      exists TXX', index n GH' = Some (GXX,TXX') /\ compat GX TX V GXX TXX TXX'.
Proof.
  intros. revert n H0. induction H.
  - intros. simpl. eauto. simpl in H0. assert (n+1 <> 0). omega.
    eapply beq_nat_false_iff in H. rewrite H in H0. inversion H0.
  - intros. simpl. destruct y.
    case_eq (beq_nat n (length l')); intros E.
    + simpl in H1. rewrite app_length in H1. simpl in H1.
      assert (n = length l'). eapply beq_nat_true_iff. eauto.
      assert (beq_nat (n+1) (length l + 1) = true). eapply beq_nat_true_iff.
      rewrite (Forall2_length _ _ _ _ _ H0). omega.
      rewrite H3 in H1. destruct x. inversion H1. subst. simpl in H.
      destruct H. subst. eexists. eauto.
    + simpl in H1. destruct x.
      assert (n <> length l'). eapply beq_nat_false_iff. eauto.
      assert (beq_nat (n+1) (length l + 1) = false). eapply beq_nat_false_iff.
      rewrite (Forall2_length _ _ _ _ _ H0). omega.
      rewrite app_length in H1. simpl in H1.
      rewrite H3 in H1.
      eapply IHForall2. eapply H1.
Qed.

Lemma compat_top: forall GX TX V G1 T1',
  compat GX TX V G1 TTop T1' -> closed 0 0 (length GX) TX -> T1' = TTop.
Proof.
  intros ? ? ? ? ? CC CLX. repeat destruct CC as [|CC]; ev; eauto.
Qed.

Lemma compat_bot: forall GX TX V G1 T1',
  compat GX TX V G1 TBot T1' -> closed 0 0 (length GX) TX -> T1' = TBot.
Proof.
  intros ? ? ? ? ? CC CLX. repeat destruct CC as [|CC]; ev; eauto.
Qed.

Lemma compat_mem: forall GX TX V G1 S1 U1 T1',
    compat GX TX V G1 (TMem S1 U1) T1' ->
    closed 0 0 (length GX) TX ->
    exists SA UA, T1' = TMem SA UA /\
                  compat GX TX V G1 S1 SA /\
                  compat GX TX V G1 U1 UA.
Proof.
  intros ? ? ? ? ? ? ? CC CLX.
  destruct CC as [|CC]; ev; subst.
  repeat eexists; eauto;
  try solve [unfold compat; left; repeat (eexists; eauto); eauto].

  destruct CC as [|CC]; ev; subst;
  inversion H; subst;
  repeat eexists; eauto; solve [unfold compat; eauto].
Qed.

Lemma compat_mem_fwd2: forall GX TX V G1 T2 T2',
    compat GX TX V G1 T2 T2' ->
    compat GX TX V G1 (TMem TBot T2) (TMem TBot T2').
Proof.
  intros. repeat destruct H as [|H]; ev; repeat eexists; eauto.
  - left. repeat (eexists; eauto); eauto. rewrite H3. eauto.
  - right. left. subst. eauto.
  - right. right. subst. simpl. eauto.
Qed.

Lemma compat_mem_fwd1: forall GX TX V G1 T1 T1',
    compat GX TX V G1 T1 T1' ->
    compat GX TX V G1 (TMem T1 TTop) (TMem T1' TTop).
Proof.
  intros. repeat destruct H as [|H]; ev; repeat eexists; eauto.
  - left. repeat (eexists; eauto); eauto. rewrite H3. eauto.
  - right. left. subst. eauto.
  - right. right. subst. simpl. eauto.
Qed.

Lemma compat_sel: forall GX TX V G1 T1' (GXX:venv) (TXX:ty) t v,
    compat GX TX V G1 (TSel t) T1' ->
    closed 0 0 (length GX) TX ->
    closed 0 0 (length GXX) TXX ->
    peval G1 t v ->
    val_type GXX v TXX ->
    exists TXX', T1' = (TSel t) /\ compat GX TX V GXX TXX TXX'.
Proof.
  intros ? ? ? ? ? ? ? ? ? CC CL CL1 IX HV. repeat destruct CC as [|CC]; subst;
  ev; subst; repeat (eexists; eauto); eauto;
  try solve [simpl; erewrite (proj2 closed_no_subst); eauto using peval_closed];
  right; left; eauto.
Qed.

Lemma compat_selh: forall GX TX V G1 T1' GH0 GH0' (GXX:venv) (TXX:ty) x,
    compat GX TX V G1 (TSel (tvar (varH x))) T1' ->
    closed 0 0 (length GX) TX ->
    index x (GH0 ++ [(GX, TX)]) = Some (GXX, TXX) ->
    Forall2 (compat2 GX TX V) GH0 GH0' ->
    (x = 0 /\ GXX = GX /\ TXX = TX) \/
    exists TXX',
      x > 0 /\ T1' = TSel (tvar (varH (x-1))) /\
      index (x-1) GH0' = Some (GXX, TXX') /\
      compat GX TX V GXX TXX TXX'
.
Proof.
  intros ? ? ? ? ? ? ? ? ? ? CC CL IX FA.

  case_eq (beq_nat x 0); intros E.
  - left. assert (x = 0). eapply beq_nat_true_iff. eauto. subst x.
    rewrite index_hit0 in IX. inversion IX. eauto.
  - right. assert (x <> 0). eapply beq_nat_false_iff. eauto.
    assert (x > 0). unfold id. unfold id in H. omega.
    eapply (index_compat_miss0) in FA. destruct FA.
    destruct CC.

    destruct H2. destruct H2. destruct H2. destruct H3. destruct H4. destruct H5.
    simpl in H6.
    rewrite E in H6.
    eexists. split. omega. split; eauto.

    simpl in H2. destruct H2. destruct H2.
    inversion H2; subst. inversion H8; subst. inversion H7; subst. omega.

    destruct H2. rewrite E in H3.
    eexists. eauto.

    assert (x-1+1=x) as A. omega. rewrite A. eauto.
Qed.

Lemma compat_all: forall GX TX V G1 T1 T2 T1' n,
    compat GX TX V G1 (TAll T1 T2) T1' ->
    closed 0 0 (length GX) TX -> closed 1 (n+1) (length G1) T2 ->
    exists TA TB, T1' = TAll TA TB /\
                  closed 1 n (length G1) TB /\
                  compat GX TX V G1 T1 TA /\
                  compat GX TX V G1 (open_rec 0 (tvar (varH (n+1))) T2) (open_rec 0 (tvar (varH n)) TB).
Proof.
  intros ? ? ? ? ? ? ? ? CC CLX CL2. destruct CC.

  ev. simpl in H0. repeat (eexists; eauto); eauto.
  eapply closed_subst; eauto.
  eapply tm_closed_upgrade_free. eapply peval_closed; eauto. omega.
  unfold compat. left. repeat (eexists; eauto); eauto.
  unfold compat. left. repeat (eexists; eauto); eauto.
  erewrite subst_open_commute; eauto using peval_closed. 

  destruct H. destruct H. inversion H. repeat (eexists; eauto). subst.
  eapply closed_upgrade_free. eauto. omega. unfold compat. eauto.
  unfold compat. eauto. right. right. subst.
  split. eapply nosubst_open. simpl. omega. eapply nosubst_intro. eauto. symmetry.
  assert (T2 = subst (tvar (varF 0)) T2) as A. symmetry. eapply closed_no_subst. eauto.
  remember (open_rec 0 (tvar (varH n)) T2) as XX. rewrite A in HeqXX. subst XX.
  eapply subst_open_commute. eauto. econstructor. eauto.

  simpl in H. destruct H. destruct H. repeat eexists. eauto. eapply closed_nosubst. eauto. eauto.
  unfold compat. right. right. eauto.
  unfold compat. right. right. split. eapply nosubst_open. simpl. omega. eauto.
  erewrite subst_open_commute. eauto. eauto. econstructor. eauto.
Qed.

Lemma compat_closed: forall GX TX V G T T' j,
  compat GX TX V G T T' ->
  closed 0 (j + 1) (length G) T ->
  closed 0 0 (length GX) TX ->
  closed 0 j (length G) T'.
Proof.
  intros. inversion H;[|destruct H2;[|destruct H2]].
  - destruct H2 as [x1 [v [Hindex [HeqV [HGX [Hv Heq]]]]]]. subst.
    apply closed_subst. eassumption.
    eapply tm_closed_upgrade_free. eapply peval_closed. eauto. omega.
  - destruct H2. subst.
    eapply closed_upgrade_free. eapply H2. omega.
  - subst.
    apply closed_nosubst. assumption. eauto.
Qed.

Lemma stp2_substitute_aux: forall n, forall G1 G2 T1 T2 GH m n1,
   stp2 false m G1 T1 G2 T2 GH n1 ->
   n1 <= n ->
   forall GH0 GH0' GX TX T1' T2' V,
     GX = base V ->
     GH = (GH0 ++ [(GX, TX)]) ->
     val_type (base V) V TX ->
     closed 0 0 (length GX) TX ->
     compat GX TX (Some V) G1 T1 T1' ->
     compat GX TX (Some V) G2 T2 T2' ->
     Forall2 (compat2 GX TX (Some V)) GH0 GH0' ->
     stpd2 false m G1 T1' G2 T2' GH0'.
Proof.
  intros n. induction n.
  Case "z". intros. inversion H0. subst. inversion H; eauto.
  intros G1 G2 T1 T2 GH m n1 H NE. remember false as s.
  induction H; inversion Heqs.

   - Case "top".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? ? CX IX1 IX2 FA.
    eapply compat_top in IX2.
    subst. eapply stpd2_top.
    eapply compat_closed. eassumption.
    rewrite app_length in H. simpl in H.
    erewrite <- Forall2_length. eapply H. eassumption.
    eassumption. assumption.

  - Case "bot".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? ? CX IX1 IX2 FA.
    eapply compat_bot in IX1.
    subst. eapply stpd2_bot.
    eapply compat_closed. eassumption.
    rewrite app_length in H. simpl in H.
    erewrite <- Forall2_length. eapply H. eassumption.
    eassumption. assumption.

  - Case "mem".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? ? CX IX1 IX2 FA.
    eapply compat_mem in IX1. repeat destruct IX1 as [? IX1].
    eapply compat_mem in IX2. repeat destruct IX2 as [? IX2].
    subst. eapply stpd2_mem.
    eapply IHn; eauto; try omega.
    eapply IHn; eauto; try omega.
    eauto. eauto.

  - Case "sel1".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? ? CX IX1 IX2 FA.

    assert (length GH = length GH0 + 1). subst GH. eapply app_length.
    assert (length GH0 = length GH0') as EL. eapply Forall2_length. eauto.

    eapply (compat_sel GXX TXX (Some V) G1 T1' (base v) TX) in IX1. repeat destruct IX1 as [? IX1].

    assert (compat GXX TXX (Some V) (base v) TX TX) as CPX. right. left. eauto.

    subst.
    eapply stpd2_sel1. eauto. eauto. eauto.
    eapply IHn; eauto; try omega.
    eapply compat_mem_fwd2. eauto.
    eauto. eauto. eauto. eauto.

  - Case "sel2".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? ? CX IX1 IX2 FA.

    assert (length GH = length GH0 + 1). subst GH. eapply app_length.
    assert (length GH0 = length GH0') as EL. eapply Forall2_length. eauto.

    eapply (compat_sel GXX TXX (Some V) G2 T2' (base v) TX) in IX2. repeat destruct IX2 as [? IX2].

    assert (compat GXX TXX (Some V) (base v) TX TX) as CPX. right. left. eauto.

    subst.
    eapply stpd2_sel2. eauto. eauto. eauto.
    eapply IHn; eauto; try omega.
    eapply compat_mem_fwd1. eauto.
    eauto. eauto. eauto. eauto.

  - Case "selx".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? ? CX IX1 IX2 FA.

    assert (length GH = length GH0 + 1). subst GH. eapply app_length.
    assert (length GH0 = length GH0') as EL. eapply Forall2_length. eauto.

    assert (T1' = TSel (varF x1)). {
      destruct IX1. ev. eauto.
      destruct H6. ev. auto.
      destruct H6. ev. eauto.
    }
    assert (T2' = TSel (varF x2)). {
      destruct IX2. ev. eauto.
      destruct H7. ev. auto.
      destruct H7. ev. eauto.
    }
    subst.
    eapply stpd2_selx. eauto. eauto.

  - Case "sela1".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? ? CX IX1 IX2 FA.

    assert (length GH = length GH0 + 1). subst GH. eapply app_length.
    assert (length GH0 = length GH0') as EL. eapply Forall2_length. eauto.

    assert (compat GXX TXX (Some V) G1 (TSel (varH x)) T1') as IXX. eauto.

    eapply (compat_selh GXX TXX (Some V) G1 T1' GH0 GH0' GX TX) in IX1. repeat destruct IX1 as [? IX1].

    destruct IX1.
    + SCase "x = 0".
      repeat destruct IXX as [|IXX]; ev.
      * subst. simpl. inversion H8; subst.
        eapply stpd2_sel1. eauto. eauto. eauto.
        eapply IHn; eauto; try omega. right. left. auto.
        eapply compat_mem_fwd2. eauto.
      * subst. inversion H7. subst. omega.
      * subst. destruct H7. eauto.
    + SCase "x > 0".
      ev. subst.
      eapply stpd2_sela1. eauto.
      assert (x-1+1=x) as A by omega.
      remember (x-1) as x1. rewrite <- A in H0.
      eapply compat_closed. eauto. eauto. eauto.
      eapply IHn; eauto; try omega.
      eapply compat_mem_fwd2. eauto.
    (* remaining obligations *)
    + eauto. + subst GH. eauto. + eauto.

  - Case "sela2".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? ? CX IX1 IX2 FA.

    assert (length GH = length GH0 + 1). subst GH. eapply app_length.
    assert (length GH0 = length GH0') as EL. eapply Forall2_length. eauto.

    assert (compat GXX TXX (Some V) G2 (TSel (varH x)) T2') as IXX. eauto.

    eapply (compat_selh GXX TXX (Some V) G2 T2' GH0 GH0' GX TX) in IX2. repeat destruct IX2 as [? IX2].

    destruct IX2.
    + SCase "x = 0".
      repeat destruct IXX as [|IXX]; ev.
      * subst. simpl. inversion H8; subst.
        eapply stpd2_sel2. eauto. eauto. eauto.
        eapply IHn; eauto; try omega. right. left. auto.
        eapply compat_mem_fwd1. eauto.
      * subst. inversion H7. subst. omega.
      * subst. destruct H7. eauto.
    + SCase "x > 0".
      ev. subst.
      eapply stpd2_sela2. eauto.
      assert (x-1+1=x) as A by omega.
      remember (x-1) as x1. rewrite <- A in H0.
      eapply compat_closed. eauto. eauto. eauto.
      eapply IHn; eauto; try omega.
      eapply compat_mem_fwd1. eauto.
    (* remaining obligations *)
    + eauto. + subst GH. eauto. + eauto.

  - Case "selax".

    intros GH0 GH0' GXX TXX T1' T2' V ? ? ? CX IX1 IX2 FA.

    assert (length GH = length GH0 + 1). subst GH. eapply app_length.
    assert (length GH0 = length GH0') as EL. eapply Forall2_length. eauto.

    assert (compat GXX TXX (Some V) G1 (TSel (varH x)) T1') as IXX1. eauto.
    assert (compat GXX TXX (Some V) G2 (TSel (varH x)) T2') as IXX2. eauto.

    destruct v as [GX TX].
    eapply (compat_selh GXX TXX (Some V) G1 T1' GH0 GH0' GX TX) in IX1. repeat destruct IX1 as [? IX1].
    eapply (compat_selh GXX TXX (Some V) G2 T2' GH0 GH0' GX TX) in IX2. repeat destruct IX2 as [? IX2].

    assert (not (nosubst (TSel (varH 0)))). unfold not. intros. simpl in H1. eauto.
    assert (not (closed 0 0 (length G1) (TSel (varH 0)))). unfold not. intros. inversion H6. omega.
    assert (not (closed 0 0 (length G2) (TSel (varH 0)))). unfold not. intros. inversion H7. omega.

    destruct x; destruct IX1; ev; try omega; destruct IX2; ev; try omega; subst.
    + SCase "x = 0".
      repeat destruct IXX1 as [IXX1|IXX1]; ev; try contradiction.
      repeat destruct IXX2 as [IXX2|IXX2]; ev; try contradiction.
      * SSCase "sel-sel".
        subst. simpl. inversion H16; subst. inversion H2; subst.
        eapply stpd2_selx. eauto. eauto.
    + SCase "x > 0".
      destruct IXX1; destruct IXX2; ev; subst; eapply stpd2_selax; eauto.
    (* leftovers *)
    + eauto. + subst. eauto. + eauto. + eauto. + subst. eauto. + eauto.

  - Case "all".
    intros GH0 GH0' GX TX T1' T2' V ? ? ? CX IX1 IX2 FA.

    assert (length GH = length GH0 + 1). subst GH. eapply app_length.
    assert (length GH0 = length GH0') as EL. eapply Forall2_length. eauto.

    eapply compat_all in IX1. repeat destruct IX1 as [? IX1].
    eapply compat_all in IX2. repeat destruct IX2 as [? IX2].

    subst.

    eapply stpd2_all.
    + eapply IHn; eauto; try omega.
    + eauto.
    + eauto.
    + eauto.
    + subst.
      eapply IHn. eauto. omega. simpl. eauto.
      change ((G2, T3) :: GH0 ++ [(base V, TX)]) with (((G2, T3) :: GH0) ++ [(base V, TX)]).
      reflexivity.
      eauto. eauto.
      rewrite app_length. simpl. rewrite EL. eauto.
      rewrite app_length. simpl. rewrite EL. eauto.
      eapply Forall2_cons. simpl. eauto. eauto.
    + eauto.
    + eauto. subst GH. rewrite <-EL. eapply closed_upgrade_free. eauto. omega.
    + eauto.
    + eauto. subst GH. rewrite <-EL. eapply closed_upgrade_free. eauto. omega.
  - Case "wrapf".
    intros. subst. eapply stpd2_wrapf. eapply IHn; eauto; try omega.
  - Case "transf".
    intros. subst.
    apply stp2_extend2 with (v1:=V) in H.
    apply stp2_extend1 with (v1:=V) in H0.
    eapply stpd2_transf.

    eapply IHn; eauto; try omega.
    unfold compat. simpl. left. exists (length G2). exists V.
    rewrite <- beq_nat_refl. split; eauto.

    eapply IHn; eauto; try omega.
    unfold compat. simpl. left. exists (length G2). exists V.
    rewrite <- beq_nat_refl. split; eauto.
Qed.

Lemma stp2_substitute: forall G1 G2 T1 T2 GH m,
   stpd2 false m G1 T1 G2 T2 GH ->
   forall GH0 GH0' GX TX T1' T2' V,
     GX = base V ->
     GH = (GH0 ++ [(GX, TX)]) ->
     val_type (base V) V TX ->
     closed 0 0 (length GX) TX ->
     compat GX TX (Some V) G1 T1 T1' ->
     compat GX TX (Some V) G2 T2 T2' ->
     Forall2 (compat2 GX TX (Some V)) GH0 GH0' ->
     stpd2 false m G1 T1' G2 T2' GH0'.
Proof.
  intros. repeat eu. eapply stp2_substitute_aux; eauto.
Qed.

(* ### Relating Static and Dynamic Subtyping ### *)
Lemma inv_vtp_half: forall G v T GH,
  val_type G v T ->
  exists T0, val_type (base v) v T0 /\ closed 0 0 (length (base v)) T0 /\
             stpd2 false false (base v) T0 G T GH.
Proof.
  intros. inversion H; subst.
  - eexists. split; try split.
    + simpl. econstructor. eassumption. ev. eapply stp2_reg1 in H1. apply H1.
    + ev. eapply stp2_closed1 in H1. simpl in H1. apply H1.
    + eapply stpd2_downgrade. ev. eexists. simpl.
      eapply stp2_extendH_mult0. eassumption.
  - eexists. split; try split.
    + simpl. econstructor; try eassumption. reflexivity. ev. eapply stp2_reg1 in H2. apply H2.
    + ev. eapply stp2_closed1 in H2. simpl in H2. apply H2.
    + eapply stpd2_downgrade. ev. eexists. simpl.
      eapply stp2_extendH_mult0. eassumption.
Qed.

Lemma exists_GYL: forall GX GY GU GL,
  wf_envh GX GY (GU ++ GL) ->
  exists GYU GYL, GY = GYU ++ GYL /\ wf_envh GX GYL GL.
Proof.
  intros. remember (GU ++ GL) as G. generalize dependent HeqG. generalize dependent GU. generalize dependent GL. induction H; intros.
  - exists []. exists []. simpl. split. reflexivity. symmetry in HeqG. apply app_eq_nil in HeqG.
    inversion HeqG. subst. eauto.
  - induction GU.
    + rewrite app_nil_l in HeqG.
      exists []. eexists. rewrite app_nil_l. split. reflexivity.
      rewrite <- HeqG. eauto.
    + simpl in HeqG. inversion HeqG.
      specialize (IHwf_envh GL GU H2). destruct IHwf_envh as [GYU [GYL [IHA IHB]]].
      exists ((vvs, a)::GYU). exists GYL. split. rewrite IHA. simpl. reflexivity.
      apply IHB.
Qed.

Lemma stp_to_stp2: forall G1 GH T1 T2,
  stp G1 GH T1 T2 ->
  forall GX GY, wf_env GX G1 -> wf_envh GX GY GH ->
  stpd2 false false GX T1 GX T2 GY.
Proof.
  intros G1 G2 T1 T2 ST. induction ST; intros GX GY WX WY; eapply stpd2_wrapf.
  - Case "top".
    eapply stpd2_top. erewrite wfh_length; eauto. erewrite wf_length; eauto.
  - Case "bot".
    eapply stpd2_bot. erewrite wfh_length; eauto. erewrite wf_length; eauto.
  - Case "mem". eapply stpd2_mem; eauto.
  - Case "sel1".
    assert (exists v : vl, index x GX = Some v /\ val_type GX v TX) as A.
    eapply index_safe_ex. eauto. eauto.
    destruct A as [? [? VT]].
    eapply inv_vtp_half in VT. ev.
    eapply stpd2_sel1. eauto. eauto. eauto. eapply stpd2_trans. eauto. eauto.
  - Case "sel2".
    assert (exists v : vl, index x GX = Some v /\ val_type GX v TX) as A.
    eapply index_safe_ex. eauto. eauto.
    destruct A as [? [? VT]].
    eapply inv_vtp_half in VT. ev.
    eapply stpd2_sel2. eauto. eauto. eauto. eapply stpd2_trans. eauto. eauto.
  - Case "selx". eauto.
    assert (exists v0 : vl, index x GX = Some v0 /\ val_type GX v0 v) as A.
    eapply index_safe_ex. eauto. eauto. eauto.
    destruct A as [? [? ?]].
    eapply stpd2_selx; eauto.
  - Case "sela1".
    assert (exists v, index x GY = Some v /\ valh_type GX GY v TX) as A.
    eapply index_safeh_ex. eauto. eauto. eauto.
    destruct A as [? [? VT]]. destruct x0.
    inversion VT. subst.
    eapply stpd2_sela1. eauto. erewrite wf_length; eauto. eauto.
  - Case "sela2".
    assert (exists v, index x GY = Some v /\ valh_type GX GY v TX) as A.
    eapply index_safeh_ex. eauto. eauto. eauto.
    destruct A as [? [? VT]]. destruct x0.
    inversion VT. subst.
    eapply stpd2_sela2. eauto. erewrite wf_length; eauto. eauto.
  - Case "selax".
    assert (exists v0, index x GY = Some v0 /\ valh_type GX GY v0 v) as A.
    eapply index_safeh_ex. eauto. eauto. eauto.
    destruct A as [? [? VT]]. destruct x0.
    destruct VT. subst.
    eapply stpd2_selax. eauto.
  - Case "all".
    subst x.
    assert (length GY = length GH) as A. eapply wfh_length; eauto.
    assert (length GX = length G1) as B. eapply wf_length; eauto.
    eapply stpd2_all. eauto. eauto.
    rewrite A. rewrite B. eauto.
    rewrite A. rewrite B. eauto.
    rewrite A.
    eapply IHST2. eauto. eapply wfeh_cons. eauto.
Qed.

(* ### Inversion Lemmas ### *)

Lemma invert_app: forall venv vf vx T1 T2,
  val_type venv vf (TAll T1 T2) ->
  val_type venv vx T1 ->
  closed 0 0 (length venv) T2 ->
  exists env tenv x y T3 T4,
    vf = (vabs env T3 y) /\
    length env = x /\
    wf_env env tenv /\
    has_type (T3::tenv) y (open (varF x) T4) /\
    stpd2 true true venv T1 env T3 [] /\
    stpd2 true true (vx::env) (open (varF x) T4) venv T2 [].
Proof.
  intros. inversion H; ev; try solve by inversion.
  inversion H5. subst.
  eexists. eexists. eexists. eexists. eexists. eexists.
  repeat split; eauto; remember (length venv1) as x.

  eapply stpd2_upgrade; eauto.
  eapply stpd2_upgrade.
  eapply inv_vtp_half with (GH:=nil) in H0. ev.
  simpl in H22.
  assert (stpd2 false false venv1 (open (varH 0) T3) venv0 (open (varH 0) T2) [(base vx, x0)]) as A. {
    eapply stpd2_narrow. eassumption. eexists. eassumption.
  }
  assert (open (varH 0) T2=T2) as EH2. {
    rewrite <- closed_no_open with (i:=0) (j:=0) (k:=(length venv0)); eauto.
  }
  assert (open (varF x) T2=T2) as EF2. {
    rewrite <- closed_no_open with (i:=0) (j:=0) (k:=(length venv0)); eauto.
  }
  rewrite EH2 in A.
  apply stp2_substitute with (GH0:=nil) (V:=vx) (GX:=base vx) (T1:=(open (varH 0) T3)) (T2:=T2) (TX:=x0) (GH:=[(base vx, x0)]); eauto.
  apply stpd2_extend1. eapply A.
  left. exists (length venv1). exists vx.
  split. simpl. rewrite <- beq_nat_refl. reflexivity.
  split. reflexivity. split. reflexivity. split. assumption.
  subst x. unfold open. erewrite subst_open_zero. reflexivity.
  simpl in H17. eapply H17.
  right. left. eauto.
Qed.

Lemma invert_dapp: forall venv vf vx xarg T1 T2,
  val_type venv vf (TAll T1 T2) ->
  val_type venv vx T1 ->
  index xarg venv = Some vx ->
  closed 0 0 (length venv) (open (varF xarg) T2) ->
  exists env tenv x y T3 T4,
    vf = (vabs env T3 y) /\
    length env = x /\
    wf_env env tenv /\
    has_type (T3::tenv) y (open (varF x) T4) /\
    stpd2 true true venv T1 env T3 [] /\
    stpd2 true true (vx::env) (open (varF x) T4) venv (open (varF xarg) T2) [].
Proof.
  intros. inversion H; ev; try solve by inversion.
  inversion H6. subst.
  eexists. eexists. eexists. eexists. eexists. eexists.
  repeat split; eauto; remember (length venv1) as x.

  eapply stpd2_upgrade; eauto.
  eapply stpd2_upgrade.
  eapply inv_vtp_half with (GH:=nil) in H0. ev.
  simpl in H23.
  assert (stpd2 false false venv1 (open (varH 0) T3) venv0 (open (varH 0) T2) [(base vx, x0)]) as A. {
    eapply stpd2_narrow. eassumption. eexists. eassumption.
  }
  apply stp2_substitute with (GH0:=nil) (V:=vx) (GX:=base vx) (T1:=(open (varH 0) T3)) (T2:=(open (varH 0) T2)) (TX:=x0) (GH:=[(base vx, x0)]); eauto.
  apply stpd2_extend1. eapply A.
  left. exists (length venv1). exists vx.
  split. simpl. rewrite <- beq_nat_refl. reflexivity.
  split. reflexivity. split. reflexivity. split. assumption.
  subst x. unfold open. erewrite subst_open_zero. reflexivity.
  simpl in H18. eapply H18.
  left. exists xarg. exists vx.
  split. assumption.
  split. reflexivity. split. reflexivity. split. assumption.
  unfold open. erewrite subst_open_zero. reflexivity.
  simpl in H20. eapply H20.
Qed.

(* ### Type Safety ### *)
(* If term type-checks and the term evaluates without timing-out,
   the result is not stuck, but a value.
*)
Theorem full_safety : forall n e tenv venv res T,
  teval n venv e = Some res -> has_type tenv e T -> wf_env venv tenv ->
  res_type venv res T.

Proof.
  intros n. induction n.
  (* 0 *)   intros. inversion H.
  (* S n *) intros. destruct e; inversion H.

  - Case "Var".
    remember (tvar i) as e. induction H0; inversion Heqe; subst.
    + destruct (index_safe_ex venv0 env T1 i) as [v [I V]]; eauto.
      rewrite I. eapply not_stuck. eapply V.

    + eapply restp_widen. eapply IHhas_type; eauto.
      eapply stpd2_upgrade. eapply stp_to_stp2; eauto.

  - Case "Typ".
    remember (ttyp t) as e. induction H0; inversion Heqe; subst.
    + eapply not_stuck. eapply v_ty; eauto.
      eapply stp2_refl. simpl. erewrite wf_length; eauto.
    + eapply restp_widen. eapply IHhas_type; eauto.
      eapply stpd2_upgrade. eapply stp_to_stp2; eauto.

  - Case "Abs".
    remember (tabs t e) as xe. induction H0; inversion Heqxe; subst.
    + eapply not_stuck. eapply v_abs; eauto.
      eapply stp2_refl. simpl. erewrite wf_length; eauto.
    + eapply restp_widen. eapply IHhas_type; eauto.
      eapply stpd2_upgrade. eapply stp_to_stp2; eauto.

  - Case "App".
    dependent induction H0.
    +
      remember (teval n venv0 e1) as tf.
      remember (teval n venv0 e2) as tx.

      destruct tx as [rx|]; try solve by inversion.
      assert (res_type venv0 rx T1) as HRX. SCase "HRX". subst. eapply IHn; eauto.
      inversion HRX as [? vx].

      destruct tf as [rf|]; subst rx; try solve by inversion.
      assert (res_type venv0 rf (TAll T1 T2)) as HRF. SCase "HRF". subst. eapply IHn; eauto.
      inversion HRF as [? vf].

      destruct (invert_app venv0 vf vx T1 T2) as
          [env1 [tenv [x0 [y0 [T3 [T4 [EF [FRX [WF [HTY [STX STY]]]]]]]]]]].
      eauto. eauto. erewrite wf_length; eauto.
      (* now we know it's a closure, and we have has_type evidence *)

      assert (res_type (vx::env1) res (open (varF x0) T4)) as HRY.
        SCase "HRY".
          subst. eapply IHn. eauto. eauto.
          (* wf_env x *) econstructor. eapply valtp_widen; eauto.
                         eapply stpd2_extend2. eauto. eauto.

      inversion HRY as [? vy].

      eapply not_stuck. eapply valtp_widen; eauto.

    +
      remember (teval n venv0 e1) as tf.
      remember (teval n venv0 (tvar x)) as tx.

      destruct tx as [rx|]; try solve by inversion.
      assert (res_type venv0 rx T1) as HRX. SCase "HRX". subst. eapply IHn; eauto.
      inversion HRX as [? vx].

      destruct tf as [rf|]; try solve by inversion.
      assert (res_type venv0 rf (TAll T1 T2)) as HRF. SCase "HRF". subst. eapply IHn; eauto.
      inversion HRF as [? vf].

      destruct (invert_dapp venv0 vf vx x T1 T2) as
          [env1 [tenv [x0 [y0 [T3 [T4 [EF [FRX [WF [HTY [STX STY]]]]]]]]]]].
      eauto. eauto.
      destruct n. inversion Heqtx. simpl in Heqtx. inversion Heqtx.
      subst rx. symmetry. assumption.
      erewrite wf_length; eauto.
      (* now we know it's a closure, and we have has_type evidence *)

      assert (res_type (vx::env1) res (open (varF x0) T4)) as HRY.
        SCase "HRY".
          subst. eapply IHn. eauto. eauto.
          (* wf_env x *) econstructor. eapply valtp_widen; eauto.
          eapply stpd2_extend2. eauto.
          (* wf_env   *) eauto.
      inversion HRY as [? vy].

      eapply not_stuck. eapply valtp_widen; eauto.

      destruct rx. solve by inversion. solve by inversion.

    + eapply restp_widen. eapply IHhas_type; eauto.
      eapply stpd2_upgrade. eapply stp_to_stp2; eauto.

Qed.
