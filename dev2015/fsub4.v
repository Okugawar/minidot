(* Full safety for F-sub *)
(* values well-typed with respect to runtime environment *)
(* inversion lemma structure *)

(* this version adds bottom and lower bounds to fsub0.v *)
(* it also turns types into proper first class objects, *)
(* compared to fsub1.v *)

(* this version adds mutable references to fsub2.v *)
(*
   compared to fsub3.v, it does NOT have the limitation:
   the underlying type of a mutable reference must be well-formed in empty env
 *)

Require Export SfLib.

Require Export Arith.EqNat.
Require Export Arith.Le.

Module FSUB.

Definition id := nat.

Inductive ty : Type :=
  | TBool  : ty
  | TBot   : ty
  | TTop   : ty
  | TFun   : ty -> ty -> ty
  | TMem   : ty -> ty -> ty
  | TCell  : ty -> ty
  | TSel   : id -> ty
  | TSelH  : id -> ty
  | TSelB  : id -> ty
  | TAll   : ty -> ty -> ty
.

Inductive tm : Type :=
  | ttrue  : tm
  | tfalse : tm
  | tvar   : id -> tm
  | tnew   : tm -> tm
  | tget   : tm -> tm
  | tset   : tm -> tm -> tm
  | ttyp   : ty -> tm
  | tapp   : tm -> tm -> tm (* f(x) *)
  | tabs   : id -> id -> tm -> tm (* \f x.y *)
  | ttapp  : tm -> tm -> tm (* f[X] *)
  | ttabs  : id -> ty -> tm -> tm (* \f x.y *)
.

Inductive vl : Type :=
| vty   : list (id*vl) -> ty -> vl
| vbool : bool -> vl
| vloc  : id -> vl
| vabs  : list (id*vl) -> id -> id -> tm -> vl
| vtabs : list (id*vl) -> id -> ty -> tm -> vl
.


Definition tenv := list (id*ty).
Definition venv := list (id*vl).
Definition aenv := list (id*(venv*ty)).

Hint Unfold venv.
Hint Unfold tenv.

Fixpoint fresh {X: Type} (l : list (id * X)): nat :=
  match l with
    | [] => 0
    | (n',a)::l' => 1 + n'
  end.

Fixpoint index {X : Type} (n : id) (l : list (id * X)) : option X :=
  match l with
    | [] => None
    | (n',a) :: l'  =>
      if le_lt_dec (fresh l') n' then
        if (beq_nat n n') then Some a else index n l'
      else None
  end.

Fixpoint indexr {X : Type} (n : id) (l : list (id * X)) : option X :=
  match l with
    | [] => None
    | (n',a) :: l'  => (* DeBrujin *)
      if (beq_nat n (length l')) then Some a else indexr n l'
  end.


Fixpoint update {X : Type} (n : nat) (x: X)
               (l : list X) { struct l }: list X :=
  match l with
    | [] => []
    | a :: l'  => if beq_nat n (length l') then x::l' else a :: update n x l'
  end.

(* LOCALLY NAMELESS *)

Inductive closed_rec: nat -> nat -> ty -> Prop :=
| cl_top: forall k l,
    closed_rec k l TTop
| cl_bot: forall k l,
    closed_rec k l TBot
| cl_bool: forall k l,
    closed_rec k l TBool
| cl_fun: forall k l T1 T2,
    closed_rec k l T1 ->
    closed_rec k l T2 ->
    closed_rec k l (TFun T1 T2)
| cl_mem: forall k l T1 T2,
    closed_rec k l T1 ->
    closed_rec k l T2 ->
    closed_rec k l (TMem T1 T2)
| cl_cell: forall k l T1,
    closed_rec k l T1 ->
    closed_rec k l (TCell T1)
| cl_bind: forall k l T1 T2,
    closed_rec k l T1 ->
    closed_rec (S k) l T2 ->
    closed_rec k l (TAll T1 T2)
| cl_sel: forall k l x,
    closed_rec k l (TSel x)
| cl_selh: forall k l x,
    l > x ->
    closed_rec k l (TSelH x)
| cl_selb: forall k l i,
    k > i ->
    closed_rec k l (TSelB i)
.

Hint Constructors closed_rec.

Definition closed j l T := closed_rec j l T.


Fixpoint open_rec (k: nat) (u: ty) (T: ty) { struct T }: ty :=
  match T with
    | TSel x      => TSel x (* free var remains free. functional, so we can't check for conflict *)
    | TSelH i     => TSelH i (*if beq_nat k i then u else TSelH i *)
    | TSelB i     => if beq_nat k i then u else TSelB i
    | TAll T1 T2  => TAll (open_rec k u T1) (open_rec (S k) u T2)
    | TTop        => TTop
    | TBot        => TBot
    | TBool       => TBool
    | TCell T1    => TCell (open_rec k u T1)
    | TMem T1 T2  => TMem (open_rec k u T1) (open_rec k u T2)
    | TFun T1 T2  => TFun (open_rec k u T1) (open_rec k u T2)
  end.

Definition open u T := open_rec 0 u T.

(* sanity check *)
Example open_ex1: open (TSel 9) (TAll TBool (TFun (TSelB 1) (TSelB 0))) =
                      (TAll TBool (TFun (TSel 9) (TSelB 0))).
Proof. compute. eauto. Qed.


Fixpoint subst (U : ty) (T : ty) {struct T} : ty :=
  match T with
    | TTop         => TTop
    | TBot         => TBot
    | TBool        => TBool
    | TCell T1     => TCell (subst U T1)
    | TMem T1 T2   => TMem (subst U T1) (subst U T2)
    | TFun T1 T2   => TFun (subst U T1) (subst U T2)
    | TSelB i      => TSelB i
    | TSel i       => TSel i
    | TSelH i      => if beq_nat i 0 then U else TSelH (i-1)
    | TAll T1 T2   => TAll (subst U T1) (subst U T2)
  end.

Fixpoint nosubst (T : ty) {struct T} : Prop :=
  match T with
    | TTop         => True
    | TBot         => True
    | TBool        => True
    | TCell T1     => nosubst T1
    | TMem T1 T2   => nosubst T1 /\ nosubst T2
    | TFun T1 T2   => nosubst T1 /\ nosubst T2
    | TSelB i      => True
    | TSel i       => True
    | TSelH i      => i <> 0
    | TAll T1 T2   => nosubst T1 /\ nosubst T2
  end.


Hint Unfold open.
Hint Unfold closed.

(*
the first env is for variables bound in terms
the second env is for variables bound in types
first = TSel, second = TSelH
*)
Inductive stp: tenv -> tenv -> ty -> ty -> Prop :=
| stp_topx: forall G1 GH,
    stp G1 GH TTop TTop
| stp_botx: forall G1 GH,
    stp G1 GH TBot TBot
| stp_top: forall G1 GH T1,
    stp G1 GH T1 T1 -> (* regularity *)
    stp G1 GH T1 TTop
| stp_bot: forall G1 GH T2,
    stp G1 GH T2 T2 -> (* regularity *)
    stp G1 GH TBot T2
| stp_bool: forall G1 GH,
    stp G1 GH TBool TBool
| stp_cell: forall G1 GH T1 T2,
    stp G1 GH T1 T2 ->
    stp G1 GH T2 T1 ->
    stp G1 GH (TCell T1) (TCell T2)
| stp_fun: forall G1 GH T1 T2 T3 T4,
    stp G1 GH T3 T1 ->
    stp G1 GH T2 T4 ->
    stp G1 GH (TFun T1 T2) (TFun T3 T4)
| stp_mem: forall G1 GH T1 T2 T3 T4,
    stp G1 GH T3 T1 ->
    stp G1 GH T2 T4 ->
    stp G1 GH (TMem T1 T2) (TMem T3 T4)
| stp_sel1: forall G1 GH TX T2 x,
    index x G1 = Some TX ->
    closed 0 0 TX ->
    stp G1 GH TX (TMem TBot T2) ->
    stp G1 GH T2 T2 -> (* regularity of stp2 *)
    stp G1 GH (TSel x) T2
| stp_sel2: forall G1 GH TX T1 x,
    index x G1 = Some TX ->
    closed 0 0 TX ->
    stp G1 GH TX (TMem T1 TTop) ->
    stp G1 GH T1 T1 -> (* regularity of stp2 *)
    stp G1 GH T1 (TSel x)
| stp_selx: forall G1 GH TX x,
    index x G1 = Some TX ->
    stp G1 GH (TSel x) (TSel x)
| stp_sela1: forall G1 GH TX T2 x,
    indexr x GH = Some TX ->
    closed 0 x TX ->
    stp G1 GH TX (TMem TBot T2) ->
    stp G1 GH T2 T2 -> (* regularity of stp2 *)
    stp G1 GH (TSelH x) T2
| stp_sela2: forall G1 GH TX T1 x,
    indexr x GH = Some TX ->
    closed 0 x TX ->
    stp G1 GH TX (TMem T1 TTop) ->
    stp G1 GH T1 T1 -> (* regularity of stp2 *)
    stp G1 GH T1 (TSelH x)
| stp_selax: forall G1 GH TX x,
    indexr x GH = Some TX  ->
    stp G1 GH (TSelH x) (TSelH x)
| stp_all: forall G1 GH T1 T2 T3 T4 x,
    stp G1 GH T3 T1 ->
    x = length GH ->
    closed 1 (length GH) T2 -> (* must not accidentally bind x *)
    closed 1 (length GH) T4 ->
    stp G1 ((0,T1)::GH) (open (TSelH x) T2) (open (TSelH x) T2) -> (* regularity *)
    stp G1 ((0,T3)::GH) (open (TSelH x) T2) (open (TSelH x) T4) ->
    stp G1 GH (TAll T1 T2) (TAll T3 T4)
.

Hint Constructors stp.

Inductive has_type : tenv -> tm -> ty -> Prop :=
| t_true: forall env,
           has_type env ttrue TBool
| t_false: forall env,
           has_type env tfalse TBool
| t_var: forall x env T1,
           index x env = Some T1 ->
           stp env [] T1 T1 ->
           has_type env (tvar x) T1
| t_typ: forall env T1,
           stp env [] T1 T1 ->
           has_type env (ttyp T1) (TMem T1 T1)
| t_new: forall env x T1,
           has_type env x T1 ->
           stp env [] T1 T1 ->
           has_type env (tnew x) (TCell T1)
| t_get: forall env T1 x,
           has_type env x (TCell T1) ->
           has_type env (tget x) T1
| t_set: forall env T1 x y,
           has_type env x (TCell T1) ->
           has_type env y T1 ->
           has_type env (tset x y) T1
| t_app: forall env f x T1 T2,
           has_type env f (TFun T1 T2) ->
           has_type env x T1 ->
           has_type env (tapp f x) T2
| t_abs: forall env f x y T1 T2,
           has_type ((x,T1)::(f,TFun T1 T2)::env) y T2 ->
           stp env [] (TFun T1 T2) (TFun T1 T2) ->
           fresh env <= f ->
           1+f <= x ->
           has_type env (tabs f x y) (TFun T1 T2)
| t_tapp: forall env f x T11 T12,
           has_type env f (TAll T11 T12) ->
           has_type env x T11 ->
           stp env [] T12 T12 ->
           has_type env (ttapp f x) T12
(*
NOTE: both the POPLmark paper and Cardelli's paper use this rule:
Does it make a difference? It seems like we can always widen f?

| t_tapp: forall env f T2 T11 T12 ,
           has_type env f (TAll T11 T12) ->
           stp env T2 T11 ->
           has_type env (ttapp f T2) (open T2 T12)

*)
| t_tabs: forall env x y T1 T2,
           has_type ((x,T1)::env) y (open (TSel x) T2) ->
           stp env [] (TAll T1 T2) (TAll T1 T2) ->
           fresh env = x ->
           has_type env (ttabs x T1 y) (TAll T1 T2)

| t_sub: forall env e T1 T2,
           has_type env e T1 ->
           stp env [] T1 T2 ->
           has_type env e T2
.


Definition base (v:vl): venv :=
  match v with
    | vty GX _ => GX
    | vbool _ => nil
    | vloc _ => nil
    | vabs GX _ _ _ => GX
    | vtabs GX _ _ _ => GX
  end.

Inductive stp2: bool -> bool -> venv -> ty -> venv -> ty -> list(id*(venv*ty)) -> list (id*(venv*ty)) -> nat -> Prop :=
| stp2_topx: forall m G1 G2 STO GH n1,
    stp2 m true G1 TTop G2 TTop STO GH (S n1)
| stp2_botx: forall m G1 G2 STO GH n1,
    stp2 m true G1 TBot G2 TBot STO GH (S n1)
| stp2_top: forall m G1 G2 STO GH T n1,
    stp2 m true G1 T G1 T STO GH n1 -> (* regularity *)
    stp2 m true G1 T G2 TTop STO GH (S n1)
| stp2_bot: forall m G1 G2 STO GH T n1,
    stp2 m true G2 T G2 T STO GH n1 -> (* regularity *)
    stp2 m true G1 TBot G2 T STO GH (S n1)
| stp2_bool: forall m G1 G2 STO GH n1,
    stp2 m true G1 TBool G2 TBool STO GH (S n1)
| stp2_fun: forall m G1 G2 T1 T2 T3 T4 STO GH n1 n2,
    stp2 false false G2 T3 G1 T1 STO GH n1 ->
    stp2 false false G1 T2 G2 T4 STO GH n2 ->
    stp2 m true G1 (TFun T1 T2) G2 (TFun T3 T4) STO GH (S (n1+n2))
| stp2_mem: forall G1 G2 T1 T2 T3 T4 STO GH n1 n2,
    stp2 true false G2 T3 G1 T1 STO GH n1 ->
    stp2 true true G1 T2 G2 T4 STO GH n2 ->
    stp2 true true G1 (TMem T1 T2) G2 (TMem T3 T4) STO GH (S (n1+n2))
| stp2_mem2: forall G1 G2 T1 T2 T3 T4 STO GH n1 n2,
    stp2 false false G2 T3 G1 T1 STO GH n1 ->
    stp2 false false G1 T2 G2 T4 STO GH n2 ->
    stp2 false true G1 (TMem T1 T2) G2 (TMem T3 T4) STO GH (S (n1+n2))
| stp2_cell: forall m G1 G2 T1 T2 STO GH n1 n2,
    stp2 false false G2 T2 G1 T1 STO GH n1 ->
    stp2 false false G1 T1 G2 T2 STO GH n2 ->
    stp2 m true G1 (TCell T1) G2 (TCell T2) STO GH (S (n1+n2))

(* strong version, with precise/invertible bounds *)
| stp2_strong_sel1: forall G1 G2 GX TX x T2 STO GH n1,
    index x G1 = Some (vty GX TX) ->
    val_type STO GX (vty GX TX) (TMem TX TX) -> (* for downgrade *)
    closed 0 0 TX ->
    stp2 true true GX TX G2 T2 STO GH n1 ->
    stp2 true true G1 (TSel x) G2 T2 STO GH (S n1)

| stp2_strong_sel2: forall G1 G2 GX TX x T1 STO GH n1,
    index x G2 = Some (vty GX TX) ->
    val_type STO GX (vty GX TX) (TMem TX TX) -> (* for downgrade *)
    closed 0 0 TX ->
    stp2 true false G1 T1 GX TX STO GH n1 ->
    stp2 true true G1 T1 G2 (TSel x) STO GH (S n1)

| stp2_strong_selx: forall G1 G2 v x1 x2 STO GH n1,
    index x1 G1 = Some v ->
    index x2 G2 = Some v ->
    stp2 true true G1 (TSel x1) G2 (TSel x2) STO GH (S n1)


(* existing object, but imprecise type *)
| stp2_sel1: forall G1 G2 GX TX x T2 STO GH n1 n2 v,
    index x G1 = Some v ->
    val_type STO GX v TX ->
    closed 0 0 TX ->
    stp2 false false GX TX G2 (TMem TBot T2) STO GH n1 ->
    stp2 false true G2 T2 G2 T2 STO GH n2 -> (* regularity *)
    stp2 false true G1 (TSel x) G2 T2 STO GH (S (n1+n2))

| stp2_sel2: forall G1 G2 GX TX x T1 STO GH n1 n2 v,
    index x G2 = Some v ->
    val_type STO GX v TX ->
    closed 0 0 TX ->
    stp2 false false GX TX G1 (TMem T1 TTop) STO GH n1 ->
    stp2 false true G1 T1 G1 T1 STO GH n2 -> (* regularity *)
    stp2 false true G1 T1 G2 (TSel x) STO GH (S (n1+n2))

| stp2_selx: forall G1 G2 v x1 x2 STO GH n1,
    index x1 G1 = Some v ->
    index x2 G2 = Some v ->
    stp2 false true G1 (TSel x1) G2 (TSel x2) STO GH (S n1)

(* hypothetical object *)
| stp2_sela1: forall G1 G2 GX TX x T2 STO GH n1 n2,
    indexr x GH = Some (GX, TX) ->
    closed 0 x TX ->
    stp2 false false GX TX G2 (TMem TBot T2) STO GH n1 ->
    stp2 false true G2 T2 G2 T2 STO GH n2 -> (* regularity *)
    stp2 false true G1 (TSelH x) G2 T2 STO GH (S (n1+n2))

| stp2_sela2: forall G1 G2 GX TX x T1 STO GH n1 n2,
    indexr x GH = Some (GX, TX) ->
    closed 0 x TX ->
    stp2 false false GX TX G1 (TMem T1 TTop) STO GH n1 ->
    stp2 false true G1 T1 G1 T1 STO GH n2 -> (* regularity *)
    stp2 false true G1 T1 G2 (TSelH x) STO GH (S (n1+n2))


| stp2_selax: forall G1 G2 GX TX x STO GH n1,
    indexr x GH = Some (GX, TX) ->
    stp2 false true G1 (TSelH x) G2 (TSelH x) STO GH (S n1)


| stp2_all: forall m G1 G2 T1 T2 T3 T4 STO GH n1 n1' n2,
    stp2 false false G2 T3 G1 T1 STO GH n1 ->
    closed 1 (length GH) T2 -> (* must not accidentally bind x *)
    closed 1 (length GH) T4 ->
    stp2 false false G1 (open (TSelH (length GH)) T2) G1 (open (TSelH (length GH)) T2) STO ((0,(G1, T1))::GH) n1' -> (* regularity *)
    stp2 false false G1 (open (TSelH (length GH)) T2) G2 (open (TSelH (length GH)) T4) STO ((0,(G2, T3))::GH) n2 ->
    stp2 m true G1 (TAll T1 T2) G2 (TAll T3 T4) STO GH (S (n1+n1'+n2))

| stp2_wrapf: forall m G1 G2 T1 T2 STO GH n1,
    stp2 m true G1 T1 G2 T2 STO GH n1 ->
    stp2 m false G1 T1 G2 T2 STO GH (S n1)
| stp2_transf: forall m G1 G2 G3 T1 T2 T3 STO GH n1 n2,
    stp2 m true G1 T1 G2 T2 STO GH n1 ->
    stp2 m false G2 T2 G3 T3 STO GH n2 ->
    stp2 m false G1 T1 G3 T3 STO GH (S (n1+n2))




with wf_env : list (id*(venv*ty)) -> venv -> tenv -> Prop :=
| wfe_nil : forall sto, wf_env sto nil nil
| wfe_cons : forall sto n v t vs ts,
    val_type sto ((n,v)::vs) v t ->
    wf_env sto vs ts ->
    wf_env sto (cons (n,v) vs) (cons (n,t) ts)

with val_type : list (id*(venv*ty)) -> venv -> vl -> ty -> Prop :=
| v_ty: forall sto env venv tenv T1 TE n,
    wf_env sto venv tenv -> (* T1 wf in tenv ? *)
    stp2 true true venv (TMem T1 T1) env TE sto [] n ->
    val_type sto env (vty venv T1) TE
| v_bool: forall sto venv b TE n,
    stp2 true true [] TBool venv TE sto [] n ->
    val_type sto venv (vbool b) TE
| v_loc: forall sto venv venv1 b T1 TE n,
    indexr b sto = Some (venv1,T1) ->
    stp2 true true venv1 (TCell T1) venv TE sto [] n ->
    val_type sto venv (vloc b) TE
| v_abs: forall sto env venv tenv f x y T1 T2 TE n,
    wf_env sto venv tenv ->
    has_type ((x,T1)::(f,TFun T1 T2)::tenv) y T2 ->
    fresh venv <= f ->
    1 + f <= x ->
    stp2 true true venv (TFun T1 T2) env TE sto [] n ->
    val_type sto env (vabs venv f x y) TE
| v_tabs: forall sto env venv tenv x y T1 T2 TE n,
    wf_env sto venv tenv ->
    has_type ((x,T1)::tenv) y (open (TSel x) T2) ->
    fresh venv = x ->
    stp2 true true venv (TAll T1 T2) env TE sto [] n ->
    val_type sto env (vtabs venv x T1 y) TE
.


Inductive wf_envh : venv -> aenv -> tenv -> Prop :=
| wfeh_nil : forall vvs, wf_envh vvs nil nil
| wfeh_cons : forall n t vs vvs ts,
    wf_envh vvs vs ts ->
    wf_envh vvs (cons (n,(vvs,t)) vs) (cons (n,t) ts)
.

Inductive valh_type : venv -> aenv -> (venv*ty) -> ty -> Prop :=
| v_tya: forall aenv venv T1,
    valh_type venv aenv (venv, T1) T1
.



Definition stpd2 b G1 T1 G2 T2 STO GH := exists n, stp2 false b G1 T1 G2 T2 STO GH n.
Definition sstpd2 b G1 T1 G2 T2 STO GH := exists n, stp2 true b G1 T1 G2 T2 STO GH n.






Ltac ep := match goal with
             | [ |- stp2 ?M1 ?M2 ?G1 ?T1 ?G2 ?T2 ?GH ?N ] => assert (exists (x:nat), stp2 M1 M2 G1 T1 G2 T2 GH x) as EEX
           end.

Ltac eu := match goal with
             | H: stpd2 _ _ _ _ _ _ _ |- _ => destruct H as [? H]
             | H: sstpd2 _ _ _ _ _ _ _ |- _ => destruct H as [? H]
(*             | H: exists n: nat ,  _ |- _  =>
               destruct H as [e P] *)
           end.

Hint Constructors stp2.
Hint Unfold stpd2.

Lemma stpd2_topx: forall G1 G2 STO GH,
    stpd2 true G1 TTop G2 TTop STO GH.
Proof. intros. exists (S 0). eauto. Qed.
Lemma stpd2_botx: forall G1 G2 STO GH,
    stpd2 true G1 TBot G2 TBot STO GH.
Proof. intros. exists (S 0). eauto. Qed.
Lemma stpd2_top: forall G1 G2 STO GH T,
    stpd2 true G1 T G1 T STO GH ->
    stpd2 true G1 T G2 TTop STO GH.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_bot: forall G1 G2 STO GH T,
    stpd2 true G2 T G2 T STO GH ->
    stpd2 true G1 TBot G2 T STO GH.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_bool: forall G1 G2 STO GH,
    stpd2 true G1 TBool G2 TBool STO GH.
Proof. intros. exists (S 0). eauto. Qed.
Lemma stpd2_fun: forall G1 G2 STO GH T11 T12 T21 T22,
    stpd2 false G2 T21 G1 T11 STO GH ->
    stpd2 false G1 T12 G2 T22 STO GH ->
    stpd2 true G1 (TFun T11 T12) G2 (TFun T21 T22) STO GH.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_mem: forall G1 G2 STO GH T11 T12 T21 T22,
    stpd2 false G2 T21 G1 T11 STO GH ->
    stpd2 false G1 T12 G2 T22 STO GH ->
    stpd2 true G1 (TMem T11 T12) G2 (TMem T21 T22) STO GH.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_cell: forall G1 G2 STO GH T1 T2,
    stpd2 false G2 T2 G1 T1 STO GH ->
    stpd2 false G1 T1 G2 T2 STO GH ->
    stpd2 true G1 (TCell T1) G2 (TCell T2) STO GH.
Proof. intros. repeat eu. eauto. Qed.

Lemma stpd2_sel1: forall G1 G2 GX TX x T2 STO GH v,
    index x G1 = Some v ->
    val_type STO GX v TX ->
    closed 0 0 TX ->
    stpd2 false GX TX G2 (TMem TBot T2) STO GH ->
    stpd2 true G2 T2 G2 T2 STO GH ->
    stpd2 true G1 (TSel x) G2 T2 STO GH.
Proof. intros. repeat eu. eauto. Qed.

Lemma stpd2_sel2: forall G1 G2 GX TX x T1 STO GH v,
    index x G2 = Some v ->
    val_type STO GX v TX ->
    closed 0 0 TX ->
    stpd2 false GX TX G1 (TMem T1 TTop) STO GH ->
    stpd2 true G1 T1 G1 T1 STO GH ->
    stpd2 true G1 T1 G2 (TSel x) STO GH.
Proof. intros. repeat eu. eauto. Qed.

Lemma stpd2_selx: forall G1 G2 x1 x2 STO GH v,
    index x1 G1 = Some v ->
    index x2 G2 = Some v ->
    stpd2 true G1 (TSel x1) G2 (TSel x2) STO GH.
Proof. intros. exists (S 0). eauto. Qed.

Lemma stpd2_sela1: forall G1 G2 GX TX x T2 STO GH,
    indexr x GH = Some (GX, TX) ->
    closed 0 x TX ->
    stpd2 false GX TX G2 (TMem TBot T2) STO GH ->
    stpd2 true G2 T2 G2 T2 STO GH ->
    stpd2 true G1 (TSelH x) G2 T2 STO GH.
Proof. intros. repeat eu. eauto. Qed.

Lemma stpd2_sela2: forall G1 G2 GX TX x T1 STO GH,
    indexr x GH = Some (GX, TX) ->
    closed 0 x TX ->
    stpd2 false GX TX G1 (TMem T1 TTop) STO GH ->
    stpd2 true G1 T1 G1 T1 STO GH ->
    stpd2 true G1 T1 G2 (TSelH x) STO GH.
Proof. intros. repeat eu. eauto. Qed.


Lemma stpd2_selax: forall G1 G2 GX TX x STO GH,
    indexr x GH = Some (GX, TX) ->
    stpd2 true G1 (TSelH x) G2 (TSelH x) STO GH.
Proof. intros. exists (S 0). eauto. Qed.


Lemma stpd2_all: forall G1 G2 T1 T2 T3 T4 STO GH,
    stpd2 false G2 T3 G1 T1 STO GH ->
    closed 1 (length GH) T2 ->
    closed 1 (length GH) T4 ->
    stpd2 false G1 (open (TSelH (length GH)) T2) G1 (open (TSelH (length GH)) T2) STO ((0,(G1, T1))::GH) ->
    stpd2 false G1 (open (TSelH (length GH)) T2) G2 (open (TSelH (length GH)) T4) STO ((0,(G2, T3))::GH) ->
    stpd2 true G1 (TAll T1 T2) G2 (TAll T3 T4) STO GH.
Proof. intros. repeat eu. eauto. Qed.

Lemma stpd2_wrapf: forall G1 G2 T1 T2 STO GH,
    stpd2 true G1 T1 G2 T2 STO GH ->
    stpd2 false G1 T1 G2 T2 STO GH.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_transf: forall G1 G2 G3 T1 T2 T3 STO GH,
    stpd2 true G1 T1 G2 T2 STO GH ->
    stpd2 false G2 T2 G3 T3 STO GH ->
    stpd2 false G1 T1 G3 T3 STO GH.
Proof. intros. repeat eu. eauto. Qed.



Lemma sstpd2_wrapf: forall G1 G2 T1 T2 STO GH,
    sstpd2 true G1 T1 G2 T2 STO GH ->
    sstpd2 false G1 T1 G2 T2 STO GH.
Proof. intros. repeat eu. eexists. eapply stp2_wrapf. eauto. Qed.
Lemma sstpd2_transf: forall G1 G2 G3 T1 T2 T3 STO GH,
    sstpd2 true G1 T1 G2 T2 STO GH ->
    sstpd2 false G2 T2 G3 T3 STO GH ->
    sstpd2 false G1 T1 G3 T3 STO GH.
Proof. intros. repeat eu. eexists. eapply stp2_transf; eauto. Qed.











(*
None             means timeout
Some None        means stuck
Some (Some v))   means result v

Could use do-notation to clean up syntax.
 *)

Fixpoint teval(n: nat)(sto: venv)(env: venv)(t: tm){struct n}: option (option (venv*vl)) :=
  match n with
    | 0 => None
    | S n =>
      match t with
        | ttrue      => Some (Some (sto, vbool true))
        | tfalse     => Some (Some (sto, vbool false))
        | tvar x     => Some (match (index x env) with | Some v => Some (sto, v) | None => None end)
        | tabs f x y => Some (Some (sto, vabs env f x y))
        | ttabs x T y  => Some (Some (sto, vtabs env x T y))
        | ttyp T     => Some (Some (sto, vty env T))
        | tnew ex     =>
          match teval n sto env ex with
            | None => None
            | Some None => Some None
            | Some (Some (sto1, v)) => Some (Some ((0,v)::sto1, vloc (length sto1)))
          end
        | tget ex    =>
          match teval n sto env ex with
            | None => None
            | Some None => Some None
            | Some (Some (sto1, vbool _)) => Some None
            | Some (Some (sto1, vty _ _)) => Some None
            | Some (Some (sto1, vtabs _ _ _ _)) => Some None
            | Some (Some (sto1, vabs _ _ _ _)) => Some None
            | Some (Some (sto1, vloc i)) =>
              Some (match (indexr i sto1) with
                      | Some v => Some (sto1,v)
                      | None => None
                    end)
          end
        | tset ex ey   =>
          match teval n sto env ex with
            | None => None
            | Some None => Some None
            | Some (Some (sto1, vbool _)) => Some None
            | Some (Some (sto1, vty _ _)) => Some None
            | Some (Some (sto1, vtabs _ _ _ _)) => Some None
            | Some (Some (sto1, vabs _ _ _ _)) => Some None
            | Some (Some (sto1, vloc i)) =>
              match teval n sto1 env ey with
                | None => None
                | Some None => Some None
                | Some (Some (sto2, v)) => Some (Some (update i (0,v) sto2, v))
              end
          end
        | tapp ef ex   =>
          match teval n sto env ex with
            | None => None
            | Some None => Some None
            | Some (Some (sto1, vx)) =>
              match teval n sto1 env ef with
                | None => None
                | Some None => Some None
                | Some (Some (sto2, vbool _)) => Some None
                | Some (Some (sto2, vty _ _)) => Some None
                | Some (Some (sto2, vloc _)) => Some None
                | Some (Some (sto2, vtabs _ _ _ _)) => Some None
                | Some (Some (sto2, vabs env2 f x ey)) =>
                  teval n sto2 ((x,vx)::(f,vabs env2 f x ey)::env2) ey
              end
          end
        | ttapp ef ex   =>
          match teval n sto env ex with
            | None => None
            | Some None => Some None
            | Some (Some (sto1, vx)) =>
              match teval n sto1 env ef with
                | None => None
                | Some None => Some None
                | Some (Some (sto2, vbool _)) => Some None
                | Some (Some (sto2, vty _ _)) => Some None
                | Some (Some (sto2, vloc _)) => Some None
                | Some (Some (sto2, vabs _ _ _ _)) => Some None
                | Some (Some (sto2, vtabs env2 x T ey)) =>
                  teval n sto2 ((x,vx)::env2) ey
              end
          end
      end
  end.


Hint Constructors ty.
Hint Constructors tm.
Hint Constructors vl.

Hint Constructors closed_rec.
Hint Constructors has_type.
Hint Constructors val_type.
Hint Constructors wf_env.
Hint Constructors stp.
Hint Constructors stp2.

Hint Constructors option.
Hint Constructors list.

Hint Unfold index.
Hint Unfold length.
Hint Unfold closed.
Hint Unfold open.

Hint Resolve ex_intro.



(* ############################################################ *)
(* Examples *)
(* ############################################################ *)


(*
match goal with
        | |- has_type _ (tvar _) _ =>
          try solve [apply t_vara;
                      repeat (econstructor; eauto)]
          | _ => idtac
      end;
*)

Ltac crush_has_tp :=
  try solve [eapply stp_selx; compute; eauto; crush_has_tp];
  try solve [eapply stp_selax; compute; eauto; crush_has_tp];
  try solve [eapply cl_selb; compute; eauto; crush_has_tp];
  try solve [(econstructor; compute; eauto; crush_has_tp)].

Ltac crush2 :=
  try solve [(eapply stp_selx; compute; eauto; crush2)];
  try solve [(eapply stp_selax; compute; eauto; crush2)];
  try solve [(eapply stp_sel1; compute; eauto; crush2)];
  try solve [(eapply stp_sela1; compute; eauto; crush2)];
  try solve [(eapply cl_selb; compute; eauto; crush2)];
  try solve [(econstructor; compute; eauto; crush2)];
  try solve [(eapply t_sub; eapply t_var; compute; eauto; crush2)].


(* define polymorphic identity function *)

Definition polyId := TAll (TMem TBot TTop) (TFun (TSelB 0) (TSelB 0)).

Example ex1: has_type [] (ttabs 0 (TMem TBot TTop) (tabs 1 2 (tvar 2))) polyId.
Proof.
  crush2.
Qed.


(* instantiate it to bool *)

Example ex2: has_type [(0,polyId)] (ttapp (tvar 0) (ttyp TBool)) (TFun TBool TBool).
Proof.
  eapply t_tapp. eapply t_sub. eapply t_var. simpl. eauto.
  eapply stp_all. eauto. eauto. crush_has_tp. crush_has_tp. crush_has_tp.
  compute. crush_has_tp.
  eapply stp_all. instantiate (1:= (TMem TBool TBool)).
    eapply stp_mem. crush2. crush2. crush2. crush2. crush2.
    eapply stp_fun. crush2. crush2. crush2.
  eapply t_sub. eapply t_typ. crush2. crush2.

  eapply stp_fun; crush2.
Qed.


Example rex1: has_type [] (tnew (ttabs 0 (TMem TBot TTop) (tabs 1 2 (tvar 2)))) (TCell polyId).
Proof.
  crush2.
Qed.

Example rex2: has_type [(0, TCell polyId)] (ttapp (tget (tvar 0)) (ttyp TBool)) (TFun TBool TBool).
Proof.
  unfold polyId. eapply t_tapp.
  eapply t_sub. eapply t_get. eapply t_var. compute. eauto. crush2.
  instantiate (1:=(TMem TBool TBool)). crush2. crush2. crush2.
Qed.

(* define brand / unbrand client function *)

Definition brandUnbrand :=
  TAll (TMem TBot TTop)
       (TFun
          (TFun TBool (TSelB 0)) (* brand *)
          (TFun
             (TFun (TSelB 0) TBool) (* unbrand *)
             TBool)).

Example ex3:
  has_type []
           (ttabs 0 (TMem TBot TTop)
                  (tabs 1 2
                        (tabs 3 4
                              (tapp (tvar 4) (tapp (tvar 2) ttrue)))))
           brandUnbrand.
Proof.
  crush2.
Qed.


(* instantiating it at bool is admissible *)

Example ex4:
  has_type [(1,TFun TBool TBool);(0,brandUnbrand)]
           (tvar 0) (TAll (TMem TBool TBool) (TFun (TFun TBool TBool) (TFun (TFun TBool TBool) TBool))).
Proof.
  eapply t_sub. crush2. crush2.
Qed.

Hint Resolve ex4.

(* apply it to identity functions *)

Example ex5:
  has_type [(1,TFun TBool TBool);(0,brandUnbrand)]
           (tapp (tapp (ttapp (tvar 0) (ttyp TBool)) (tvar 1)) (tvar 1)) TBool.
Proof.
  crush2.
Qed.





(* ############################################################ *)
(* Proofs *)
(* ############################################################ *)





Lemma wf_fresh : forall sto vs ts,
                    wf_env sto vs ts ->
                    (fresh vs = fresh ts).
Proof.
  intros. induction H. auto.
  compute. eauto.
Qed.

Hint Immediate wf_fresh.


Lemma wfh_length : forall vvs vs ts,
                    wf_envh vvs vs ts ->
                    (length vs = length ts).
Proof.
  intros. induction H. auto.
  compute. eauto.
Qed.

Hint Immediate wf_fresh.

Lemma index_max : forall X vs n (T: X),
                       index n vs = Some T ->
                       n < fresh vs.
Proof.
  intros X vs. induction vs.
  - Case "nil". intros. inversion H.
  - Case "cons".
    intros. inversion H. destruct a.
    case_eq (le_lt_dec (fresh vs) i); intros ? E1.
    + SCase "ok".
      rewrite E1 in H1.
      case_eq (beq_nat n i); intros E2.
      * SSCase "hit".
        eapply beq_nat_true in E2. subst n. compute. eauto.
      * SSCase "miss".
        rewrite E2 in H1.
        assert (n < fresh vs). eapply IHvs. apply H1.
        compute. omega.
    + SCase "bad".
      rewrite E1 in H1. inversion H1.
Qed.

Lemma indexr_max : forall X vs n (T: X),
                       indexr n vs = Some T ->
                       n < length vs.
Proof.
  intros X vs. induction vs.
  - Case "nil". intros. inversion H.
  - Case "cons".
    intros. inversion H. destruct a.
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

Lemma index_extend : forall X vs n n' x (T: X),
                       index n vs = Some T ->
                       fresh vs <= n' ->
                       index n ((n',x)::vs) = Some T.

Proof.
  intros.
  assert (n < fresh vs). eapply index_max. eauto.
  assert (n <> n'). omega.
  assert (beq_nat n n' = false) as E. eapply beq_nat_false_iff; eauto.
  assert (fresh vs <= n') as E2. omega.
  elim (le_xx (fresh vs) n' E2). intros ? EX.
  unfold index. unfold index in H. rewrite H. rewrite E. rewrite EX. reflexivity.
Qed.

Lemma indexr_extend : forall X vs n n' x (T: X),
                       indexr n vs = Some T ->
                       indexr n ((n',x)::vs) = Some T.

Proof.
  intros.
  assert (n < length vs). eapply indexr_max. eauto.
  assert (beq_nat n (length vs) = false) as E. eapply beq_nat_false_iff. omega.
  unfold indexr. unfold indexr in H. rewrite H. rewrite E. reflexivity.
Qed.


(* splicing -- for stp_extend. *)

Fixpoint splice n (T : ty) {struct T} : ty :=
  match T with
    | TTop         => TTop
    | TBot         => TBot
    | TBool        => TBool
    | TCell T1     => TCell (splice n T1)
    | TMem T1 T2   => TMem (splice n T1) (splice n T2)
    | TFun T1 T2   => TFun (splice n T1) (splice n T2)
    | TSelB i      => TSelB i
    | TSel i       => TSel i
    | TSelH i      => if le_lt_dec n i  then TSelH (i+1) else TSelH i
    | TAll T1 T2   => TAll (splice n T1) (splice n T2)
  end.

Definition splicett n (V: (id*ty)) :=
  match V with
    | (x,T) => (x,(splice n T))
  end.

Definition spliceat n (V: (id*(venv*ty))) :=
  match V with
    | (x,(G,T)) => (x,(G,splice n T))
  end.

Lemma splice_open_permute: forall {X} (G0:list (id*X)) T2 n j,
(open_rec j (TSelH (n + S (length G0))) (splice (length G0) T2)) =
(splice (length G0) (open_rec j (TSelH (n + length G0)) T2)).
Proof.
  intros X G T. induction T; intros; simpl; eauto;
  try rewrite IHT1; try rewrite IHT2; try rewrite IHT; eauto.

  case_eq (le_lt_dec (length G) i); intros E LE; simpl; eauto.
  case_eq (beq_nat j i); intros E; simpl; eauto.
  case_eq (le_lt_dec (length G) (n + length G)); intros EL LE.
  assert (n + S (length G) = n + length G + 1). omega.
  rewrite H. eauto.
  omega.
Qed.

Lemma indexr_splice_hi: forall G0 G2 x0 x v1 T,
    indexr x0 (G2 ++ G0) = Some T ->
    length G0 <= x0 ->
    indexr (x0 + 1) (map (splicett (length G0)) G2 ++ (x, v1) :: G0) = Some (splice (length G0) T).
Proof.
  intros G0 G2. induction G2; intros.
  - eapply indexr_max in H. simpl in H. omega.
  - simpl in H. destruct a.
    case_eq (beq_nat x0 (length (G2 ++ G0))); intros E.
    + rewrite E in H. inversion H. subst. simpl.
      rewrite app_length in E.
      rewrite app_length. rewrite map_length. simpl.
      assert (beq_nat (x0 + 1) (length G2 + S (length G0)) = true). eapply beq_nat_true_iff. eapply beq_nat_true_iff in E. omega.
      rewrite H1. eauto.
    + rewrite E in H.  eapply IHG2 in H. eapply indexr_extend. eapply H. eauto.
Qed.

Lemma indexr_spliceat_hi: forall G0 G2 x0 x v1 G T,
    indexr x0 (G2 ++ G0) = Some (G, T) ->
    length G0 <= x0 ->
    indexr (x0 + 1) (map (spliceat (length G0)) G2 ++ (x, v1) :: G0) = Some (G, splice (length G0) T).
Proof.
  intros G0 G2. induction G2; intros.
  - eapply indexr_max in H. simpl in H. omega.
  - simpl in H. destruct a.
    case_eq (beq_nat x0 (length (G2 ++ G0))); intros E.
    + rewrite E in H. inversion H. subst. simpl.
      rewrite app_length in E.
      rewrite app_length. rewrite map_length. simpl.
      assert (beq_nat (x0 + 1) (length G2 + S (length G0)) = true). eapply beq_nat_true_iff. eapply beq_nat_true_iff in E. omega.
      rewrite H1. eauto.
    + rewrite E in H.  eapply IHG2 in H. destruct p. eapply indexr_extend. eapply H. eauto.
Qed.

Lemma plus_lt_contra: forall a b,
  a + b < b -> False.
Proof.
  intros a b H. induction a.
  - simpl in H. apply lt_irrefl in H. assumption.
  - simpl in H. apply IHa. omega.
Qed.

Lemma indexr_splice_lo0: forall {X} G0 G2 x0 (T:X),
    indexr x0 (G2 ++ G0) = Some T ->
    x0 < length G0 ->
    indexr x0 G0 = Some T.
Proof.
  intros X G0 G2. induction G2; intros.
  - simpl in H. apply H.
  - simpl in H. destruct a.
    case_eq (beq_nat x0 (length (G2 ++ G0))); intros E.
    + eapply beq_nat_true_iff in E. subst.
      rewrite app_length in H0. apply plus_lt_contra in H0. inversion H0.
    + rewrite E in H. apply IHG2. apply H. apply H0.
Qed.

Lemma indexr_extend_mult: forall {X} G0 G2 x0 (T:X),
    indexr x0 G0 = Some T ->
    indexr x0 (G2++G0) = Some T.
Proof.
  intros X G0 G2. induction G2; intros.
  - simpl. assumption.
  - destruct a. simpl.
    case_eq (beq_nat x0 (length (G2 ++ G0))); intros E.
    + eapply beq_nat_true_iff in E.
      apply indexr_max in H. subst.
      rewrite app_length in H. apply plus_lt_contra in H. inversion H.
    + apply IHG2. assumption.
Qed.

Lemma indexr_splice_lo: forall G0 G2 x0 x v1 T f,
    indexr x0 (G2 ++ G0) = Some T ->
    x0 < length G0 ->
    indexr x0 (map (splicett f) G2 ++ (x, v1) :: G0) = Some T.
Proof.
  intros.
  assert (indexr x0 G0 = Some T). eapply indexr_splice_lo0; eauto.
  eapply indexr_extend_mult. eapply indexr_extend. eauto.
Qed.

Lemma indexr_spliceat_lo: forall G0 G2 x0 x v1 G T f,
    indexr x0 (G2 ++ G0) = Some (G, T) ->
    x0 < length G0 ->
    indexr x0 (map (spliceat f) G2 ++ (x, v1) :: G0) = Some (G, T).
Proof.
  intros.
  assert (indexr x0 G0 = Some (G, T)). eapply indexr_splice_lo0; eauto.
  eapply indexr_extend_mult. eapply indexr_extend. eauto.
Qed.


Lemma fresh_splice_ctx: forall G n,
  fresh G = fresh (map (splicett n) G).
Proof.
  intros. induction G.
  - simpl. reflexivity.
  - destruct a. simpl. reflexivity.
Qed.

Lemma index_splice_ctx: forall G x T n,
  index x G = Some T ->
  index x (map (splicett n) G) = Some (splice n T).
Proof.
  intros. induction G.
  - simpl in H. inversion H.
  - destruct a. simpl in H.
    case_eq (le_lt_dec (fresh G) i); intros E LE; rewrite LE in H.
    case_eq (beq_nat x i); intros Eq; rewrite Eq in H.
    inversion H. simpl. erewrite <- (fresh_splice_ctx). rewrite LE.
    rewrite Eq. reflexivity.
    simpl. erewrite <- (fresh_splice_ctx). rewrite LE.
    rewrite Eq. apply IHG. apply H.
    inversion H.
Qed.

Lemma closed_splice: forall j l T n,
  closed j l T ->
  closed j (S l) (splice n T).
Proof.
  intros. induction H; simpl; eauto.
  case_eq (le_lt_dec n x); intros E LE.
  unfold closed. apply cl_selh. omega.
  unfold closed. apply cl_selh. omega.
Qed.

Lemma map_splice_length_inc: forall G0 G2 x v1,
   (length (map (splicett (length G0)) G2 ++ (x, v1) :: G0)) = (S (length (G2 ++ G0))).
Proof.
  intros. rewrite app_length. rewrite map_length. induction G2.
  - simpl. reflexivity.
  - simpl. eauto.
Qed.

Lemma map_spliceat_length_inc: forall G0 G2 x v1,
   (length (map (spliceat (length G0)) G2 ++ (x, v1) :: G0)) = (S (length (G2 ++ G0))).
Proof.
  intros. rewrite app_length. rewrite map_length. induction G2.
  - simpl. reflexivity.
  - simpl. eauto.
Qed.


Lemma closed_inc: forall j l T,
  closed j l T ->
  closed j (S l) T.
Proof.
  intros. induction H; simpl; eauto.
  unfold closed. apply cl_selh. omega.
Qed.

Lemma closed_inc_mult: forall j l l' T,
  closed j l T ->
  l' >= l ->
  closed j l' T.
Proof.
  intros j l l' T H LE. induction LE.
  - assumption.
  - apply closed_inc. assumption.
Qed.

Lemma closed_splice_idem: forall k l T n,
                            closed k l T ->
                            n >= l ->
                            splice n T = T.
Proof.
  intros. induction H; eauto.
  simpl.
  rewrite IHclosed_rec1. rewrite IHclosed_rec2.
  reflexivity.
  assumption. assumption.
  simpl.
  rewrite IHclosed_rec1. rewrite IHclosed_rec2.
  reflexivity.
  assumption. assumption.
  simpl.
  rewrite IHclosed_rec.
  reflexivity.
  assumption.
  simpl.
  rewrite IHclosed_rec1. rewrite IHclosed_rec2.
  reflexivity.
  assumption. assumption.
  simpl.
  case_eq (le_lt_dec n x); intros E LE. omega. reflexivity.
Qed.

Ltac ev := repeat match goal with
                    | H: exists _, _ |- _ => destruct H
                    | H: _ /\  _ |- _ => destruct H
           end.

Lemma stp_closed : forall G GH T1 T2,
                     stp G GH T1 T2 ->
                     closed 0 (length GH) T1 /\ closed 0 (length GH) T2.
Proof.
  intros. induction H;
    try solve [repeat ev; split; eauto];
    try solve [try inversion IHstp; split; eauto; apply cl_selh; eapply indexr_max; eassumption];
    try solve [inversion IHstp1 as [IH1 IH2]; inversion IH2; split; eauto; apply cl_selh; eapply indexr_max; eassumption].
Qed.

Lemma stp_closed2 : forall G1 GH T1 T2,
                       stp G1 GH T1 T2 ->
                       closed 0 (length GH) T2.
Proof.
  intros. apply (proj2 (stp_closed G1 GH T1 T2 H)).
Qed.

Lemma stp_closed1 : forall G1 GH T1 T2,
                       stp G1 GH T1 T2 ->
                       closed 0 (length GH) T1.
Proof.
  intros. apply (proj1 (stp_closed G1 GH T1 T2 H)).
Qed.

Lemma stp2_closed: forall G1 G2 T1 T2 STO GH s m n1,
                     stp2 s m G1 T1 G2 T2 STO GH n1 ->
                     closed 0 (length GH) T1 /\ closed 0 (length GH) T2.
  intros. induction H;
    try solve [repeat ev; split; eauto];
    try solve [try inversion IHstp2_1; try inversion IHstp2_2; split; eauto; apply cl_selh; eapply indexr_max; eassumption];
    try solve [inversion IHstp2 as [IH1 IH2]; inversion IH2; split; eauto; apply cl_selh; eapply indexr_max; eassumption].
Qed.

Lemma stp2_closed2 : forall G1 G2 T1 T2 STO GH s m n1,
                       stp2 s m G1 T1 G2 T2 STO GH n1 ->
                       closed 0 (length GH) T2.
Proof.
  intros. apply (proj2 (stp2_closed G1 G2 T1 T2 STO GH s m n1 H)).
Qed.

Lemma stp2_closed1 : forall G1 G2 T1 T2 STO GH s m n1,
                       stp2 s m G1 T1 G2 T2 STO GH n1 ->
                       closed 0 (length GH) T1.
Proof.
  intros. apply (proj1 (stp2_closed G1 G2 T1 T2 STO GH s m n1 H)).
Qed.

Lemma valtp_closed: forall STO G v T,
  val_type STO G v T -> closed 0 0 T.
Proof.
  intros. inversion H; subst; repeat ev;
  match goal with
      [ H : stp2 ?s ?m ?G1 ?T1 G T STO [] ?n |- _ ] =>
      eapply stp2_closed2 in H; simpl in H; apply H
  end.
Qed.


Lemma stp_splice : forall GX G0 G1 T1 T2 x v1,
   stp GX (G1++G0) T1 T2 ->
   stp GX ((map (splicett (length G0)) G1) ++ (x,v1)::G0) (splice (length G0) T1) (splice (length G0) T2).
Proof.
  intros GX G0 G1 T1 T2 x v1 H. remember (G1++G0) as G.
  revert G0 G1 HeqG.
  induction H; intros; subst GH; simpl; eauto.
  - Case "sel1".
    eapply stp_sel1. apply H. assumption.
    assert (splice (length G0) TX=TX) as A. {
      eapply closed_splice_idem. eassumption. omega.
    }
    rewrite <- A. apply IHstp1. reflexivity.
    apply IHstp2. reflexivity.
  - Case "sel2".
    eapply stp_sel2. apply H. assumption.
    assert (splice (length G0) TX=TX) as A. {
      eapply closed_splice_idem. eassumption. omega.
    }
    rewrite <- A. apply IHstp1. reflexivity.
    apply IHstp2. reflexivity.
  - Case "sela1".
    case_eq (le_lt_dec (length G0) x0); intros E LE.
    + eapply stp_sela1. eapply indexr_splice_hi. eauto. eauto.
      eapply closed_splice in H0. assert (S x0 = x0 +1) as A by omega.
      rewrite <- A. eapply H0.
      eapply IHstp1. eauto.
      eapply IHstp2. eauto.
    + eapply stp_sela1. eapply indexr_splice_lo. eauto. eauto. eauto. eauto.
      assert (splice (length G0) TX=TX) as A. {
        eapply closed_splice_idem. eassumption. omega.
      }
      rewrite <- A. eapply IHstp1. eauto.
      eapply IHstp2. eauto.
  - Case "sela2".
    case_eq (le_lt_dec (length G0) x0); intros E LE.
    + eapply stp_sela2. eapply indexr_splice_hi. eauto. eauto.
      eapply closed_splice in H0. assert (S x0 = x0 +1) as A by omega.
      rewrite <- A. eapply H0.
      eapply IHstp1. eauto.
      eapply IHstp2. eauto.
    + eapply stp_sela2. eapply indexr_splice_lo. eauto. eauto. eauto. eauto.
      assert (splice (length G0) TX=TX) as A. {
        eapply closed_splice_idem. eassumption. omega.
      }
      rewrite <- A. eapply IHstp1. eauto.
      eapply IHstp2. eauto.
  - Case "selax".
    case_eq (le_lt_dec (length G0) x0); intros E LE.
    + eapply stp_selax. eapply indexr_splice_hi. eauto. eauto.
    + eapply stp_selax. eapply indexr_splice_lo. eauto. eauto.
  - Case "all".
    eapply stp_all.
    eapply IHstp1. eauto. eauto. eauto.

    simpl. rewrite map_splice_length_inc. apply closed_splice. assumption.

    simpl. rewrite map_splice_length_inc. apply closed_splice. assumption.

    specialize IHstp2 with (G3:=G0) (G4:=(0, T1) :: G2).
    simpl in IHstp2. rewrite app_length. rewrite map_length. simpl.
    repeat rewrite splice_open_permute with (j:=0). subst x0.
    rewrite app_length in IHstp2. simpl in IHstp2.
    eapply IHstp2. eauto.

    specialize IHstp3 with (G3:=G0) (G4:=(0, T3) :: G2).
    simpl in IHstp2. rewrite app_length. rewrite map_length. simpl.
    repeat rewrite splice_open_permute with (j:=0). subst x0.
    rewrite app_length in IHstp3. simpl in IHstp3.
    eapply IHstp3. eauto.
Qed.

Lemma stp2_splice : forall G1 T1 G2 T2 STO GH1 GH0 x v1 s m n1,
   stp2 s m G1 T1 G2 T2 STO (GH1++GH0) n1 ->
   stp2 s m G1 (splice (length GH0) T1) G2 (splice (length GH0) T2) STO ((map (spliceat (length GH0)) GH1) ++ (x,v1)::GH0) n1.
Proof.
  intros G1 T1 G2 T2 STO GH1 GH0 x v1 s m n1 H. remember (GH1++GH0) as GH.
  revert GH0 GH1 HeqGH.
  induction H; intros; subst GH; simpl; eauto.
  - Case "strong_sel1".
    eapply stp2_strong_sel1. apply H. eassumption. assumption.
    assert (splice (length GH0) TX=TX) as A. {
      eapply closed_splice_idem. eassumption. omega.
    }
    rewrite <- A. apply IHstp2.
    reflexivity.
  - Case "strong_sel2".
    eapply stp2_strong_sel2. apply H. eassumption. assumption.
    assert (splice (length GH0) TX=TX) as A. {
      eapply closed_splice_idem. eassumption. omega.
    }
    rewrite <- A. apply IHstp2.
    reflexivity.
  - Case "sel1".
    eapply stp2_sel1. apply H. eassumption. assumption.
    assert (splice (length GH0) TX=TX) as A. {
      eapply closed_splice_idem. eassumption. omega.
    }
    rewrite <- A. apply IHstp2_1.
    reflexivity.
    apply IHstp2_2. reflexivity.
  - Case "sel2".
    eapply stp2_sel2. apply H. eassumption. assumption.
    assert (splice (length GH0) TX=TX) as A. {
      eapply closed_splice_idem. eassumption. omega.
    }
    rewrite <- A. apply IHstp2_1.
    reflexivity.
    apply IHstp2_2. reflexivity.
  - Case "sela1".
    case_eq (le_lt_dec (length GH0) x0); intros E LE.
    + eapply stp2_sela1. eapply indexr_spliceat_hi. apply H. eauto.
      eapply closed_splice in H0. assert (S x0 = x0 +1) as EQ by omega. rewrite <- EQ.
      eapply H0.
      eapply IHstp2_1. eauto.
      eapply IHstp2_2. eauto.
    + eapply stp2_sela1. eapply indexr_spliceat_lo. apply H. eauto. eauto.
      assert (splice (length GH0) TX=TX) as A. {
        eapply closed_splice_idem. eassumption. omega.
      }
      rewrite <- A. eapply IHstp2_1. eauto. eapply IHstp2_2. eauto.
  - Case "sela2".
    case_eq (le_lt_dec (length GH0) x0); intros E LE.
    + eapply stp2_sela2. eapply indexr_spliceat_hi. apply H. eauto.
      eapply closed_splice in H0. assert (S x0 = x0 +1) as EQ by omega. rewrite <- EQ.
      eapply H0.
      eapply IHstp2_1. eauto.
      eapply IHstp2_2. eauto.
    + eapply stp2_sela2. eapply indexr_spliceat_lo. apply H. eauto. eauto.
      assert (splice (length GH0) TX=TX) as A. {
        eapply closed_splice_idem. eassumption. omega.
      }
      rewrite <- A. eapply IHstp2_1. eauto. eapply IHstp2_2. eauto.
  - Case "selax".
    case_eq (le_lt_dec (length GH0) x0); intros E LE.
    + eapply stp2_selax.
      eapply indexr_spliceat_hi. apply H. eauto.
    + eapply stp2_selax.
      eapply indexr_spliceat_lo. apply H. eauto.
  - Case "all".
    eapply stp2_all.
    eapply IHstp2_1. reflexivity.

    simpl. rewrite map_spliceat_length_inc. apply closed_splice. assumption.

    simpl. rewrite map_spliceat_length_inc. apply closed_splice. assumption.

    specialize IHstp2_2 with (GH2:=GH0) (GH3:=(0, (G1, T1)) :: GH1).
    simpl in IHstp2_2. rewrite app_length. rewrite map_length. simpl.
    repeat rewrite splice_open_permute with (j:=0).
    rewrite app_length in IHstp2_2. simpl in IHstp2_2.
    eapply IHstp2_2. reflexivity.

    specialize IHstp2_3 with (GH2:=GH0) (GH3:=(0, (G2, T3)) :: GH1).
    simpl in IHstp2_3. rewrite app_length. rewrite map_length. simpl.
    repeat rewrite splice_open_permute with (j:=0).
    rewrite app_length in IHstp2_3. simpl in IHstp2_3.
    eapply IHstp2_3. reflexivity.
Qed.

Lemma stp_extend : forall G1 GH T1 T2 x v1,
                       stp G1 GH T1 T2 ->
                       stp G1 ((x,v1)::GH) T1 T2.
Proof.
  intros. induction H; eauto using indexr_extend.
  assert (splice (length GH) T2 = T2) as A2. {
    eapply closed_splice_idem. apply H1. omega.
  }
  assert (splice (length GH) T4 = T4) as A4. {
    eapply closed_splice_idem. apply H2. omega.
  }
  assert (TSelH (S (length GH)) = splice (length GH) (TSelH (length GH))) as AH. {
    simpl. case_eq (le_lt_dec (length GH) (length GH)); intros E LE.
    simpl. rewrite NPeano.Nat.add_1_r. reflexivity.
    clear LE. apply lt_irrefl in E. inversion E.
  }
  assert (closed 0 (length GH) T1).  eapply stp_closed2. eauto.
  assert (splice (length GH) T1 = T1) as A1. {
    eapply closed_splice_idem. eauto. omega.
  }
  assert (closed 0 (length GH) T3). eapply stp_closed1. eauto.
  assert (splice (length GH) T3 = T3) as A3. {
    eapply closed_splice_idem. eauto. omega.
  }
  assert (map (splicett (length GH)) [(0,T1)] ++(x,v1)::GH =((0,T1)::(x,v1)::GH)) as HGX1. {
    simpl. rewrite A1. eauto.
  }
  assert (map (splicett (length GH)) [(0,T3)] ++(x,v1)::GH =((0,T3)::(x,v1)::GH)) as HGX3. {
    simpl. rewrite A3. eauto.
  }
  apply stp_all with (x:=length ((x,v1) :: GH)).
  apply IHstp1.
  reflexivity.
  apply closed_inc. apply H1.
  apply closed_inc. apply H2.
  simpl.
  rewrite <- A2. rewrite <- A2.
  unfold open.
  change (TSelH (S (length GH))) with (TSelH (0 + (S (length GH)))).
  rewrite -> splice_open_permute.
  rewrite <- HGX1.
  apply stp_splice.
  rewrite A2. simpl. unfold open in H3. rewrite <- H0. apply H3.
  simpl.
  rewrite <- A2. rewrite <- A4.
  unfold open.
  change (TSelH (S (length GH))) with (TSelH (0 + (S (length GH)))).
  rewrite -> splice_open_permute. rewrite -> splice_open_permute.
  rewrite <- HGX3.
  apply stp_splice.
  simpl. unfold open in H4. rewrite <- H0. apply H4.
Qed.

Lemma indexr_at_index: forall {A} x0 GH0 GH1 x (v:A),
  beq_nat x0 (length GH1) = true ->
  indexr x0 (GH0 ++ (x, v) :: GH1) = Some v.
Proof.
  intros. apply beq_nat_true in H. subst.
  induction GH0.
  - simpl. rewrite <- beq_nat_refl. reflexivity.
  - destruct a. simpl.
    rewrite app_length. simpl. rewrite <- plus_n_Sm. rewrite <- plus_Sn_m.
    rewrite false_beq_nat. assumption. omega.
Qed.

Lemma indexr_same: forall {A} x0 (v0:A) GH0 GH1 x (v:A) (v':A),
  beq_nat x0 (length GH1) = false ->
  indexr x0 (GH0 ++ (x, v) :: GH1) = Some v0 ->
  indexr x0 (GH0 ++ (x, v') :: GH1) = Some v0.
Proof.
  intros ? ? ? ? ? ? ? ? E H.
  induction GH0.
  - simpl. rewrite E. simpl in H. rewrite E in H. apply H.
  - destruct a. simpl.
    rewrite app_length. simpl.
    case_eq (beq_nat x0 (length GH0 + S (length GH1))); intros E'.
    simpl in H. rewrite app_length in H. simpl in H. rewrite E' in H.
    rewrite H. reflexivity.
    simpl in H. rewrite app_length in H. simpl in H. rewrite E' in H.
    rewrite IHGH0. reflexivity. assumption.
Qed.

Inductive venv_ext : venv -> venv -> Prop :=
| venv_ext_refl : forall G, venv_ext G G
| venv_ext_cons : forall x T G1 G2, fresh G1 <= x -> venv_ext G1 G2 -> venv_ext ((x,T)::G1) G2.

Inductive aenv_ext : aenv -> aenv -> Prop :=
| aenv_ext_nil : aenv_ext nil nil
| aenv_ext_cons : forall x T G' G A A', aenv_ext A' A -> venv_ext G' G -> aenv_ext ((x,(G',T))::A') ((x,(G,T))::A).

Lemma aenv_ext_refl: forall GH, aenv_ext GH GH.
Proof.
  intros. induction GH.
  - apply aenv_ext_nil.
  - destruct a. destruct p. apply aenv_ext_cons.
    assumption.
    apply venv_ext_refl.
Qed.

Lemma index_extend_mult : forall G G' x T,
                       index x G = Some T ->
                       venv_ext G' G ->
                       index x G' = Some T.
Proof.
  intros G G' x T H HV.
  induction HV.
  - assumption.
  - apply index_extend. apply IHHV. apply H. assumption.
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

Lemma indexr_at_ext :
  forall GH GH' x T G,
    aenv_ext GH' GH ->
    indexr x GH = Some (G, T) ->
    exists G', indexr x GH' = Some (G', T) /\ venv_ext G' G.
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


Lemma stp2_closure_extend_rec :
  forall G1 G2 T1 T2 STO GH s m n1,
    stp2 s m G1 T1 G2 T2 STO GH n1 ->
    (forall G1' G2' GH',
       aenv_ext GH' GH ->
       venv_ext G1' G1 ->
       venv_ext G2' G2 ->
       stp2 s m G1' T1 G2' T2 STO GH' n1).
Proof.
  intros G1 G2 T1 T2 STO GH s m n1 H.
  induction H; intros; eauto;
  try solve [inversion IHstp2_1; inversion IHstp2_2; eauto];
  try solve [inversion IHstp2; eauto].
  - Case "strong_sel1".
    eapply stp2_strong_sel1. eapply index_extend_mult. apply H.
    assumption. eassumption. assumption.
    apply IHstp2. assumption. apply venv_ext_refl. assumption.
  - Case "strong_sel2".
    eapply stp2_strong_sel2. eapply index_extend_mult. apply H.
    assumption. eassumption. assumption.
    apply IHstp2. assumption. assumption. apply venv_ext_refl.
  - Case "strong_selx".
    eapply stp2_strong_selx.
    eapply index_extend_mult. apply H. assumption.
    eapply index_extend_mult. apply H0. assumption.
  - Case "sel1".
    eapply stp2_sel1. eapply index_extend_mult. apply H.
    assumption. eassumption. assumption.
    apply IHstp2_1. assumption. apply venv_ext_refl. assumption.
    apply IHstp2_2. assumption. assumption. assumption.
  - Case "sel2".
    eapply stp2_sel2. eapply index_extend_mult. apply H.
    assumption. eassumption. assumption.
    apply IHstp2_1. assumption. apply venv_ext_refl. assumption.
    apply IHstp2_2. assumption. assumption. assumption.
  - Case "selx".
    eapply stp2_selx.
    eapply index_extend_mult. apply H. assumption.
    eapply index_extend_mult. apply H0. assumption.
  - Case "sela1".
    assert (exists GX', indexr x GH' = Some (GX', TX) /\ venv_ext GX' GX) as A. {
      apply indexr_at_ext with (GH:=GH); assumption.
    }
    inversion A as [GX' [H' HX]].
    apply stp2_sela1 with (GX:=GX') (TX:=TX).
    assumption. assumption.
    apply IHstp2_1; assumption.
    apply IHstp2_2; assumption.
  - Case "sela2".
    assert (exists GX', indexr x GH' = Some (GX', TX) /\ venv_ext GX' GX) as A. {
      apply indexr_at_ext with (GH:=GH); assumption.
    }
    inversion A as [GX' [H' HX]].
    apply stp2_sela2 with (GX:=GX') (TX:=TX).
    assumption. assumption.
    apply IHstp2_1; assumption.
    apply IHstp2_2; assumption.
  - Case "selax".
    assert (exists GX', indexr x GH' = Some (GX', TX) /\ venv_ext GX' GX) as A. {
      apply indexr_at_ext with (GH:=GH); assumption.
    }
    inversion A as [GX' [H' HX]].
    apply stp2_selax with (GX:=GX') (TX:=TX).
    assumption.
  - Case "all".
    assert (length GH = length GH') as A. {
      apply aenv_ext__same_length. assumption.
    }
    apply stp2_all.
    apply IHstp2_1; assumption.
    subst. rewrite <- A. assumption.
    subst. rewrite <- A. assumption.
    subst. rewrite <- A.
    apply IHstp2_2. apply aenv_ext_cons. assumption. assumption. assumption. assumption.
    subst. rewrite <- A.
    apply IHstp2_3. apply aenv_ext_cons. assumption. assumption. assumption. assumption.
  - Case "trans".
    eapply stp2_transf.
    eapply IHstp2_1.
    assumption. assumption. apply venv_ext_refl.
    eapply IHstp2_2.
    assumption. apply venv_ext_refl. assumption.
Qed.


Lemma stp2_closure_extend : forall G1 T1 G2 T2 STO GH GX T x v s m n1,
                              stp2 s m G1 T1 G2 T2 STO ((0,(GX,T))::GH) n1 ->
                              fresh GX <= x ->
                              stp2 s m G1 T1 G2 T2 STO ((0,((x,v)::GX,T))::GH) n1.
Proof.
  intros. eapply stp2_closure_extend_rec. apply H.
  apply aenv_ext_cons. apply aenv_ext_refl. apply venv_ext_cons.
  assumption. apply venv_ext_refl. apply venv_ext_refl. apply venv_ext_refl.
Qed.


Lemma stp2_extend : forall x v1 G1 G2 T1 T2 STO GH s m n1,
                      stp2 s m G1 T1 G2 T2 STO GH n1 ->
                      (fresh G1 <= x ->
                       stp2 s m ((x,v1)::G1) T1 G2 T2 STO GH n1) /\
                      (fresh G2 <= x ->
                       stp2 s m G1 T1 ((x,v1)::G2) T2 STO GH n1) /\
                      (fresh G1 <= x -> fresh G2 <= x ->
                       stp2 s m ((x,v1)::G1) T1 ((x,v1)::G2) T2 STO GH n1).
Proof.
  intros. induction H;
    try solve [split; try split; repeat ev; intros; eauto using index_extend];
    try solve [split; try split; intros; inversion IHstp2_1 as [? [? ?]]; inversion IHstp2_2 as [? [? ?]]; inversion IHstp2_3 as [? [? ?]]; constructor; eauto; apply stp2_closure_extend; eauto].
Qed.

Lemma stp2_extend2 : forall x v1 G1 G2 T1 T2 STO H s m n1,
                       stp2 s m G1 T1 G2 T2 STO H n1 ->
                       fresh G2 <= x ->
                       stp2 s m G1 T1 ((x,v1)::G2) T2 STO H n1.
Proof.
  intros. apply (proj2 (stp2_extend x v1 G1 G2 T1 T2 STO H s m n1 H0)). assumption.
Qed.

Lemma stp2_extend1 : forall x v1 G1 G2 T1 T2 STO H s m n1,
                       stp2 s m G1 T1 G2 T2 STO H n1 ->
                       fresh G1 <= x ->
                       stp2 s m ((x,v1)::G1) T1 G2 T2 STO H n1.
Proof.
  intros. apply (proj1 (stp2_extend x v1 G1 G2 T1 T2 STO H s m n1 H0)). assumption.
Qed.

Lemma stp2_extendH : forall x v1 G1 G2 T1 T2 STO GH s m n1,
                       stp2 s m G1 T1 G2 T2 STO GH n1 ->
                       stp2 s m G1 T1 G2 T2 STO ((x,v1)::GH) n1.
Proof.
  intros. induction H; eauto using indexr_extend.
  assert (splice (length GH) T2 = T2) as A2. {
    eapply closed_splice_idem. apply H0. omega.
  }
  assert (splice (length GH) T4 = T4) as A4. {
    eapply closed_splice_idem. apply H1. omega.
  }
  assert (TSelH (S (length GH)) = splice (length GH) (TSelH (length GH))) as AH. {
    simpl. case_eq (le_lt_dec (length GH) (length GH)); intros E LE.
    simpl. rewrite NPeano.Nat.add_1_r. reflexivity.
    clear LE. apply lt_irrefl in E. inversion E.
  }
  assert (closed 0 (length GH) T1). eapply stp2_closed2. eauto.
  assert (splice (length GH) T1 = T1) as A1. {
    eapply closed_splice_idem. eauto. omega.
  }
  assert (map (spliceat (length GH)) [(0,(G1, T1))] ++(x,v1)::GH =((0, (G1, T1))::(x,v1)::GH)) as HGX1. {
    simpl. rewrite A1. eauto.
  }
  assert (closed 0 (length GH) T3). eapply stp2_closed1. eauto.
  assert (splice (length GH) T3 = T3) as A3. {
    eapply closed_splice_idem. eauto. omega.
  }
  assert (map (spliceat (length GH)) [(0,(G2, T3))] ++(x,v1)::GH =((0, (G2, T3))::(x,v1)::GH)) as HGX3. {
    simpl. rewrite A3. eauto.
  }
  eapply stp2_all.
  apply IHstp2_1.
  apply closed_inc. apply H0.
  apply closed_inc. apply H1.
  simpl.
  unfold open.
  rewrite <- A2.
  unfold open.
  change (TSelH (S (length GH))) with (TSelH (0 + (S (length GH)))).
  rewrite -> splice_open_permute.
  rewrite <- HGX1.
  apply stp2_splice.
  simpl. unfold open in H2. apply H2.
  simpl.
  rewrite <- A2. rewrite <- A4.
  unfold open.
  change (TSelH (S (length GH))) with (TSelH (0 + (S (length GH)))).
  rewrite -> splice_open_permute.
  rewrite -> splice_open_permute.
  rewrite <- HGX3.
  apply stp2_splice.
  simpl. unfold open in H3. apply H3.
Qed.

Lemma stp2_extendH_mult : forall G1 G2 T1 T2 STO H H2 s m n1,
                       stp2 s m G1 T1 G2 T2 STO H n1 ->
                       stp2 s m G1 T1 G2 T2 STO (H2++H) n1.
Proof.
  intros. induction H2.
  - simpl. assumption.
  - simpl. destruct a as [x v1].
    apply stp2_extendH. assumption.
Qed.

Lemma stp2_extendH_mult0 : forall G1 G2 T1 T2 STO H2 s m n1,
                       stp2 s m G1 T1 G2 T2 STO [] n1 ->
                       stp2 s m G1 T1 G2 T2 STO H2 n1.
Proof.
  intros. rewrite (app_nil_end H2).
  apply stp2_extendH_mult. assumption.
Qed.

Scheme stp2_mut := Induction for stp2 Sort Prop
with wf_env_mut := Induction for wf_env Sort Prop
with val_type_mut := Induction for val_type Sort Prop.
Combined Scheme stp2_val_env_mutind from stp2_mut, wf_env_mut, val_type_mut.

Lemma stp2_val_wf_sto_ext:
  (forall s m G1 T1 G2 T2 STO GH n1,
     stp2 s m G1 T1 G2 T2 STO GH n1 ->
     forall senv', stp2 s m G1 T1 G2 T2 (senv'++STO) GH n1) /\
  (forall senv venv env, wf_env senv venv env ->
     forall senv', wf_env (senv' ++ senv) venv env) /\
  (forall senv G v T, val_type senv G v T ->
     forall senv', val_type (senv' ++ senv) G v T).
Proof.
  apply stp2_val_env_mutind; intros; eauto using indexr_extend_mult.
Qed.

Lemma stp2_extendS_mult : forall G1 G2 T1 T2 STO STO2 GH s m n1,
                       stp2 s m G1 T1 G2 T2 STO GH n1 ->
                       stp2 s m G1 T1 G2 T2 (STO2++STO) GH n1.
Proof.
  intros. apply (proj1 stp2_val_wf_sto_ext). assumption.
Qed.

Lemma stp2_reg  : forall G1 G2 T1 T2 STO GH s m n1,
                    stp2 s m G1 T1 G2 T2 STO GH n1 ->
                    (exists n0, stp2 s true G1 T1 G1 T1 STO GH n0) /\
                    (exists n0, stp2 s true G2 T2 G2 T2 STO GH n0).
Proof.
  intros. induction H;
    try solve [repeat ev; split; eexists; eauto].
  Grab Existential Variables.
  apply 0. apply 0. apply 0. apply 0. apply 0. apply 0. apply 0. apply 0. apply 0. apply 0.
  apply 0. apply 0. apply 0. apply 0. apply 0. apply 0. apply 0. apply 0. apply 0. apply 0.
Qed.

Lemma stp2_reg2 : forall G1 G2 T1 T2 STO GH s m n1,
                       stp2 s m G1 T1 G2 T2 STO GH n1 ->
                       (exists n0, stp2 s true G2 T2 G2 T2 STO GH n0).
Proof.
  intros. apply (proj2 (stp2_reg G1 G2 T1 T2 STO GH s m n1 H)).
Qed.

Lemma stp2_reg1 : forall G1 G2 T1 T2 STO GH s m n1,
                       stp2 s m G1 T1 G2 T2 STO GH n1 ->
                       (exists n0, stp2 s true G1 T1 G1 T1 STO GH n0).
Proof.
  intros. apply (proj1 (stp2_reg G1 G2 T1 T2 STO GH s m n1 H)).
Qed.

(* not used, but for good measure *)
Lemma stp_reg  : forall G GH T1 T2,
                    stp G GH T1 T2 ->
                    stp G GH T1 T1 /\ stp G GH T2 T2.
Proof.
  intros. induction H;
    try solve [repeat ev; split; eauto].
Qed.


(* extend_mult0 *)


Inductive venv_ext0 : venv -> venv -> Prop :=
| venv_ext0_nil : forall G, venv_ext0 G nil
| venv_ext0_refl : forall G, venv_ext0 G G
.

Inductive aenv_ext0 : aenv -> aenv -> Prop :=
| aenv_ext0_nil : aenv_ext0 nil nil
| aenv_ext0_cons : forall x T G' G A A', aenv_ext0 A' A -> venv_ext0 G' G -> aenv_ext0 ((x,(G',T))::A') ((x,(G,T))::A).

Lemma aenv_ext0_refl: forall GH, aenv_ext0 GH GH.
Proof.
  intros. induction GH.
  - apply aenv_ext0_nil.
  - destruct a. destruct p. apply aenv_ext0_cons.
    assumption.
    apply venv_ext0_refl.
Qed.

Lemma index_extend_mult0 : forall G G' x T,
                       index x G = Some T ->
                       venv_ext0 G' G ->
                       index x G' = Some T.
Proof.
  intros G G' x T H HV.
  induction HV.
  - inversion H.
  - assumption.
Qed.

Lemma aenv_ext0__same_length:
  forall GH GH',
    aenv_ext0 GH' GH ->
    length GH = length GH'.
Proof.
  intros. induction H.
  - simpl. reflexivity.
  - simpl. rewrite IHaenv_ext0. reflexivity.
Qed.

Lemma indexr_at_ext0 :
  forall GH GH' x T G,
    aenv_ext0 GH' GH ->
    indexr x GH = Some (G, T) ->
    exists G', indexr x GH' = Some (G', T) /\ venv_ext0 G' G.
Proof.
  intros GH GH' x T G Hext Hindex. induction Hext.
  - simpl in Hindex. inversion Hindex.
  - simpl. simpl in Hindex.
    case_eq (beq_nat x (length A)); intros E.
    rewrite E in Hindex.  inversion Hindex. subst.
    rewrite <- (@aenv_ext0__same_length A A'). rewrite E.
    exists G'. split. reflexivity. assumption. assumption.
    rewrite E in Hindex.
    rewrite <- (@aenv_ext0__same_length A A'). rewrite E.
    apply IHHext. assumption. assumption.
Qed.

Lemma stp2_closure_extend_mult0_rec :
  forall G1 G2 T1 T2 STO GH s m n1,
    stp2 s m G1 T1 G2 T2 STO GH n1 ->
    (forall G1' G2' GH',
       aenv_ext0 GH' GH ->
       venv_ext0 G1' G1 ->
       venv_ext0 G2' G2 ->
       stp2 s m G1' T1 G2' T2 STO GH' n1).
Proof.
  intros G1 G2 T1 T2 STO GH s m n1 H.
  induction H; intros; eauto;
  try solve [inversion IHstp2_1; inversion IHstp2_2; eauto];
  try solve [inversion IHstp2; eauto].
  - Case "strong_sel1".
    eapply stp2_strong_sel1. eapply index_extend_mult0. apply H.
    assumption. eassumption. assumption.
    apply IHstp2. assumption. apply venv_ext0_refl. assumption.
  - Case "strong_sel2".
    eapply stp2_strong_sel2. eapply index_extend_mult0. apply H.
    assumption. eassumption. assumption.
    apply IHstp2. assumption. assumption. apply venv_ext0_refl.
  - Case "strong_selx".
    eapply stp2_strong_selx.
    eapply index_extend_mult0. apply H. assumption.
    eapply index_extend_mult0. apply H0. assumption.
  - Case "sel1".
    eapply stp2_sel1. eapply index_extend_mult0. apply H.
    assumption. eassumption. assumption.
    apply IHstp2_1. assumption. apply venv_ext0_refl. assumption.
    apply IHstp2_2. assumption. assumption. assumption.
  - Case "sel2".
    eapply stp2_sel2. eapply index_extend_mult0. apply H.
    assumption. eassumption. assumption.
    apply IHstp2_1. assumption. apply venv_ext0_refl. assumption.
    apply IHstp2_2. assumption. assumption. assumption.
  - Case "selx".
    eapply stp2_selx.
    eapply index_extend_mult0. apply H. assumption.
    eapply index_extend_mult0. apply H0. assumption.
  - Case "sela1".
    assert (exists GX', indexr x GH' = Some (GX', TX) /\ venv_ext0 GX' GX) as A. {
      apply indexr_at_ext0 with (GH:=GH); assumption.
    }
    inversion A as [GX' [H' HX]].
    apply stp2_sela1 with (GX:=GX') (TX:=TX).
    assumption. assumption.
    apply IHstp2_1; assumption.
    apply IHstp2_2; assumption.
  - Case "sela2".
    assert (exists GX', indexr x GH' = Some (GX', TX) /\ venv_ext0 GX' GX) as A. {
      apply indexr_at_ext0 with (GH:=GH); assumption.
    }
    inversion A as [GX' [H' HX]].
    apply stp2_sela2 with (GX:=GX') (TX:=TX).
    assumption. assumption.
    apply IHstp2_1; assumption.
    apply IHstp2_2; assumption.
  - Case "selax".
    assert (exists GX', indexr x GH' = Some (GX', TX) /\ venv_ext0 GX' GX) as A. {
      apply indexr_at_ext0 with (GH:=GH); assumption.
    }
    inversion A as [GX' [H' HX]].
    apply stp2_selax with (GX:=GX') (TX:=TX).
    assumption.
  - Case "all".
    assert (length GH = length GH') as A. {
      apply aenv_ext0__same_length. assumption.
    }
    apply stp2_all.
    apply IHstp2_1; assumption.
    subst. rewrite <- A. assumption.
    subst. rewrite <- A. assumption.
    subst. rewrite <- A.
    apply IHstp2_2. apply aenv_ext0_cons. assumption. assumption. assumption. assumption.
    subst. rewrite <- A.
    apply IHstp2_3. apply aenv_ext0_cons. assumption. assumption. assumption. assumption.
  - Case "trans".
    eapply stp2_transf.
    eapply IHstp2_1.
    assumption. assumption. apply venv_ext0_refl.
    eapply IHstp2_2.
    assumption. apply venv_ext0_refl. assumption.
Qed.

Lemma stp2_extend_mult0 : forall G1 G2 T1 T2 STO GH s m n1,
                       stp2 s m [] T1 [] T2 STO GH n1 ->
                       stp2 s m G1 T1 G2 T2 STO GH n1.
Proof.
  intros. eapply stp2_closure_extend_mult0_rec. apply H.
  apply aenv_ext0_refl. eapply venv_ext0_nil. eapply venv_ext0_nil.
Qed.

(* stpd2 variants below *)

Lemma stpd2_extend2 : forall x v1 G1 G2 T1 T2 STO H m,
                       stpd2 m G1 T1 G2 T2 STO H ->
                       fresh G2 <= x ->
                       stpd2 m G1 T1 ((x,v1)::G2) T2 STO H.
Proof.
  intros. inversion H0 as [n1 Hsub]. exists n1.
  apply stp2_extend2; assumption.
Qed.

Lemma stpd2_extend1 : forall x v1 G1 G2 T1 T2 STO H m,
                       stpd2 m G1 T1 G2 T2 STO H ->
                       fresh G1 <= x ->
                       stpd2 m ((x,v1)::G1) T1 G2 T2 STO H.
Proof.
  intros. inversion H0 as [n1 Hsub]. exists n1.
  apply stp2_extend1; assumption.
Qed.

Lemma stpd2_extendH : forall x v1 G1 G2 T1 T2 STO H m,
                       stpd2 m G1 T1 G2 T2 STO H ->
                       stpd2 m G1 T1 G2 T2 STO ((x,v1)::H).
Proof.
  intros. inversion H0 as [n1 Hsub]. exists n1.
  apply stp2_extendH; assumption.
Qed.

Lemma stpd2_extendH_mult : forall G1 G2 T1 T2 STO H H2 m,
                       stpd2 m G1 T1 G2 T2 STO H->
                       stpd2 m G1 T1 G2 T2 STO (H2++H).
Proof.
  intros. inversion H0 as [n1 Hsub]. exists n1.
  apply stp2_extendH_mult; assumption.
Qed.

Lemma stpd2_extendH_mult0 : forall G1 G2 T1 T2 STO H2 m,
                       stpd2 m G1 T1 G2 T2 STO [] ->
                       stpd2 m G1 T1 G2 T2 STO H2.
Proof.
  intros. inversion H as [n1 Hsub]. exists n1.
  apply stp2_extendH_mult0; assumption.
Qed.

Lemma stpd2_extendS_mult : forall G1 G2 T1 T2 STO STO2 H m,
                       stpd2 m G1 T1 G2 T2 STO H->
                       stpd2 m G1 T1 G2 T2 (STO2++STO) H.
Proof.
  intros. inversion H0 as [n1 Hsub]. exists n1.
  apply stp2_extendS_mult; assumption.
Qed.


Lemma stpd2_reg2 : forall G1 G2 T1 T2 STO H m,
                       stpd2 m G1 T1 G2 T2 STO H ->
                       stpd2 true G2 T2 G2 T2 STO H.
Proof.
  intros. inversion H0 as [n1 Hsub].
  eapply stp2_reg2; eassumption.
Qed.

Lemma stpd2_reg1 : forall G1 G2 T1 T2 STO H m,
                       stpd2 m G1 T1 G2 T2 STO H ->
                       stpd2 true G1 T1 G1 T1 STO H.
Proof.
  intros. inversion H0 as [n1 Hsub].
  eapply stp2_reg1; eassumption.
Qed.


Lemma stpd2_closed2 : forall G1 G2 T1 T2 STO H m,
                       stpd2 m G1 T1 G2 T2 STO H ->
                       closed 0 (length H) T2.
Proof.
  intros. inversion H0 as [n1 Hsub].
  eapply stp2_closed2; eassumption.
Qed.

Lemma stpd2_closed1 : forall G1 G2 T1 T2 STO H m,
                       stpd2 m G1 T1 G2 T2 STO H ->
                       closed 0 (length H) T1.
Proof.
  intros. inversion H0 as [n1 Hsub].
  eapply stp2_closed1; eassumption.
Qed.


(* sstpd2 variants below *)

Lemma sstpd2_extend2 : forall x v1 G1 G2 T1 T2 STO H m,
                       sstpd2 m G1 T1 G2 T2 STO H ->
                       fresh G2 <= x ->
                       sstpd2 m G1 T1 ((x,v1)::G2) T2 STO H.
Proof.
  intros. inversion H0 as [n1 Hsub]. exists n1.
  apply stp2_extend2; assumption.
Qed.

Lemma sstpd2_extend1 : forall x v1 G1 G2 T1 T2 STO H m,
                       sstpd2 m G1 T1 G2 T2 STO H ->
                       fresh G1 <= x ->
                       sstpd2 m ((x,v1)::G1) T1 G2 T2 STO H.
Proof.
  intros. inversion H0 as [n1 Hsub]. exists n1.
  apply stp2_extend1; assumption.
Qed.

Lemma sstpd2_extendH : forall x v1 G1 G2 T1 T2 STO H m,
                       sstpd2 m G1 T1 G2 T2 STO H ->
                       sstpd2 m G1 T1 G2 T2 STO ((x,v1)::H).
Proof.
  intros. inversion H0 as [n1 Hsub]. exists n1.
  apply stp2_extendH; assumption.
Qed.

Lemma sstpd2_extendH_mult : forall G1 G2 T1 T2 STO H H2 m,
                       sstpd2 m G1 T1 G2 T2 STO H ->
                       sstpd2 m G1 T1 G2 T2 STO (H2++H).
Proof.
  intros. inversion H0 as [n1 Hsub]. exists n1.
  apply stp2_extendH_mult; assumption.
Qed.

Lemma sstpd2_extendH_mult0 : forall G1 G2 T1 T2 STO H2 m,
                       sstpd2 m G1 T1 G2 T2 STO [] ->
                       sstpd2 m G1 T1 G2 T2 STO H2.
Proof.
  intros. inversion H as [n1 Hsub]. exists n1.
  apply stp2_extendH_mult0; assumption.
Qed.

Lemma sstpd2_extendS_mult : forall G1 G2 T1 T2 STO STO2 H m,
                       sstpd2 m G1 T1 G2 T2 STO H->
                       sstpd2 m G1 T1 G2 T2 (STO2++STO) H.
Proof.
  intros. inversion H0 as [n1 Hsub]. exists n1.
  apply stp2_extendS_mult; assumption.
Qed.

Lemma sstpd2_reg2 : forall G1 G2 T1 T2 STO H m,
                       sstpd2 m G1 T1 G2 T2 STO H ->
                       sstpd2 true G2 T2 G2 T2 STO H.
Proof.
  intros. inversion H0 as [n1 Hsub].
  eapply stp2_reg2; eassumption.
Qed.

Lemma sstpd2_reg1 : forall G1 G2 T1 T2 STO H m,
                       sstpd2 m G1 T1 G2 T2 STO H ->
                       sstpd2 true G1 T1 G1 T1 STO H.
Proof.
  intros. inversion H0 as [n1 Hsub].
  eapply stp2_reg1; eassumption.
Qed.

Lemma sstpd2_closed2 : forall G1 G2 T1 T2 STO H m,
                       sstpd2 m G1 T1 G2 T2 STO H ->
                       closed 0 (length H) T2.
Proof.
  intros. inversion H0 as [n1 Hsub].
  eapply stp2_closed2; eassumption.
Qed.

Lemma sstpd2_closed1 : forall G1 G2 T1 T2 STO H m,
                       sstpd2 m G1 T1 G2 T2 STO H ->
                       closed 0 (length H) T1.
Proof.
  intros. inversion H0 as [n1 Hsub].
  eapply stp2_closed1; eassumption.
Qed.




Lemma valtp_extend : forall sto vs v x v1 T,
                       val_type sto vs v T ->
                       fresh vs <= x ->
                       val_type sto ((x,v1)::vs) v T.
Proof.
  intros. induction H; eauto; econstructor; eauto; eapply stp2_extend2; eauto.
Qed.


Lemma index_safe_ex: forall STO H1 G1 TF i,
             wf_env STO H1 G1 ->
             index i G1 = Some TF ->
             exists v, index i H1 = Some v /\ val_type STO H1 v TF.
Proof. intros. induction H.
   - Case "nil". inversion H0.
   - Case "cons". inversion H0.
     case_eq (le_lt_dec (fresh ts) n); intros ? E1.
     + SCase "ok".
       rewrite E1 in H3.
       assert ((fresh ts) <= n) as QF. eauto. rewrite <-(wf_fresh sto vs ts H1) in QF.
       elim (le_xx (fresh vs) n QF). intros ? EX.

       case_eq (beq_nat i n); intros E2.
       * SSCase "hit".
         assert (index i ((n, v) :: vs) = Some v). eauto. unfold index. rewrite EX. rewrite E2. eauto.
         assert (t = TF).
         unfold index in H0. rewrite E1 in H0. rewrite E2 in H0. inversion H0. eauto.
         subst t. eauto.
       * SSCase "miss".
         rewrite E2 in H3.
         assert (exists v0, index i vs = Some v0 /\ val_type sto vs v0 TF) as HI. eapply IHwf_env. eauto.
         inversion HI as [v0 HI1]. inversion HI1.
         eexists. econstructor. eapply index_extend; eauto. eapply valtp_extend; eauto.
     + SSCase "bad".
       rewrite E1 in H3. inversion H3.
Qed.


Lemma index_safeh_ex: forall STO H1 H2 G1 GH TF i,
             wf_env STO H1 G1 -> wf_envh H1 H2 GH ->
             indexr i GH = Some TF ->
             exists v, indexr i H2 = Some v /\ valh_type H1 H2 v TF.
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
                 indexr i vs = Some v /\ valh_type vvs vs v TF). eauto.
       destruct H1. destruct H1.
       eexists. split. eapply indexr_extend. eauto.
       inversion H4. subst.
       eapply v_tya. (* aenv is not constrained -- bit of a cheat?*)
Qed.

Inductive wf_sto: list (id*(venv*ty)) -> venv -> list (id*(venv*ty)) -> Prop :=
| wfs_nil: forall G,
  wf_sto G nil nil
| wfs_cons: forall G venv v t vs ts,
  val_type G venv v t ->
  wf_sto G vs ts ->
  wf_sto G ((0,v)::vs) ((0,(venv,t))::ts)
.

Inductive res_type: list (id*(venv*ty)) -> venv -> option (venv*vl) -> ty -> Prop :=
| not_stuck: forall STO sto venv v T,
      val_type STO venv v T ->
      wf_sto STO sto STO ->
      res_type STO venv (Some (sto, v)) T.

Hint Constructors res_type.
Hint Resolve not_stuck.



Lemma stpd2_trans_aux: forall n, forall G1 G2 G3 T1 T2 T3 STO H n1,
  stp2 false false G1 T1 G2 T2 STO H n1 -> n1 < n ->
  stpd2 false G2 T2 G3 T3 STO H ->
  stpd2 false G1 T1 G3 T3 STO H.
Proof.
  intros n. induction n; intros; try omega; repeat eu; subst; inversion H0.
  - Case "wrapf". eapply stpd2_transf; eauto.
  - Case "transf". eapply stpd2_transf. eauto. eapply IHn. eauto. omega. eauto.
Qed.


Lemma sstpd2_trans_axiom_aux: forall n, forall G1 G2 G3 T1 T2 T3 STO H n1,
  stp2 true false G1 T1 G2 T2 STO H n1 -> n1 < n ->
  sstpd2 false G2 T2 G3 T3 STO H ->
  sstpd2 false G1 T1 G3 T3 STO H.
Proof.
  intros n. induction n; intros; try omega; repeat eu; subst; inversion H0.
  - Case "wrapf". eapply sstpd2_transf. eexists. eauto. eexists. eauto.
  - Case "transf". eapply sstpd2_transf. eexists. eauto. eapply IHn. eauto. omega. eexists. eauto.
Qed.

Lemma stpd2_trans: forall G1 G2 G3 T1 T2 T3 STO H,
  stpd2 false G1 T1 G2 T2 STO H ->
  stpd2 false G2 T2 G3 T3 STO H ->
  stpd2 false G1 T1 G3 T3 STO H.
Proof. intros. repeat eu. eapply stpd2_trans_aux; eauto. Qed.

Lemma sstpd2_trans_axiom: forall G1 G2 G3 T1 T2 T3 STO H,
  sstpd2 false G1 T1 G2 T2 STO H ->
  sstpd2 false G2 T2 G3 T3 STO H ->
  sstpd2 false G1 T1 G3 T3 STO H.
Proof. intros. repeat eu.
       eapply sstpd2_trans_axiom_aux; eauto.
       eexists. eauto.
Qed.

Lemma stp2_narrow_aux: forall n, forall m G1 T1 G2 T2 STO GH n0,
  stp2 false m G1 T1 G2 T2 STO GH n0 ->
  n0 <= n ->
  forall x GH1 GH0 GH' GX1 TX1 GX2 TX2,
    GH=GH1++[(x,(GX2,TX2))]++GH0 ->
    GH'=GH1++[(x,(GX1,TX1))]++GH0 ->
    stpd2 false GX1 TX1 GX2 TX2 STO GH0 ->
    stpd2 m G1 T1 G2 T2 STO GH'.
Proof.
  intros n.
  induction n.
  - Case "z". intros. inversion H0. subst. inversion H; eauto.
  - Case "s n". intros m G1 T1 G2 T2 STO GH n0 H NE. inversion H; subst;
      intros x0 GH1 GH0 GH' GX1 TX1 GX2 TX2 EGH EGH' HX; eauto.
    + SCase "top". eapply stpd2_top. eapply IHn; try eassumption. omega.
    + SCase "bot". eapply stpd2_bot. eapply IHn; try eassumption. omega.
    + SCase "fun". eapply stpd2_fun.
      eapply IHn; try eassumption. omega.
      eapply IHn; try eassumption. omega.
    + SCase "mem". eapply stpd2_mem.
      eapply IHn; try eassumption. omega.
      eapply IHn; try eassumption. omega.
    + SCase "cell". eapply stpd2_cell.
      eapply IHn; try eassumption. omega.
      eapply IHn; try eassumption. omega.
    + SCase "sel1". eapply stpd2_sel1; try eassumption.
      eapply IHn; try eassumption. omega.
      eapply IHn; try eassumption. omega.
    + SCase "sel2". eapply stpd2_sel2; try eassumption.
      eapply IHn; try eassumption. omega.
      eapply IHn; try eassumption. omega.
    + SCase "sela1".
      case_eq (beq_nat x (length GH0)); intros E.
      * assert (indexr x ([(x0, (GX2, TX2))]++GH0) = Some (GX2, TX2)) as A2. {
          simpl. rewrite E. reflexivity.
        }
        assert (indexr x GH = Some (GX2, TX2)) as A2'. {
          rewrite EGH. eapply indexr_extend_mult. apply A2.
        }
        rewrite A2' in H0. inversion H0. subst.
        inversion HX as [nx HX'].
        eapply stpd2_sela1.
        eapply indexr_extend_mult. simpl. rewrite E. reflexivity.
        apply beq_nat_true in E. rewrite E. eapply stp2_closed1. eassumption.
        eapply stpd2_trans.
        eexists. eapply stp2_extendH_mult. eapply stp2_extendH_mult. eassumption.
        eapply IHn; try eassumption. omega.
        reflexivity. reflexivity.
        eapply IHn; try eassumption. omega.
        reflexivity. reflexivity.
      * assert (indexr x GH' = Some (GX, TX)) as A. {
          subst.
          eapply indexr_same. apply E. eassumption.
        }
        eapply stpd2_sela1. eapply A. assumption.
        eapply IHn; try eassumption. omega.
        eapply IHn; try eassumption. omega.
    + SCase "sela2".
      case_eq (beq_nat x (length GH0)); intros E.
      * assert (indexr x ([(x0, (GX2, TX2))]++GH0) = Some (GX2, TX2)) as A2. {
          simpl. rewrite E. reflexivity.
        }
        assert (indexr x GH = Some (GX2, TX2)) as A2'. {
          rewrite EGH. eapply indexr_extend_mult. apply A2.
        }
        rewrite A2' in H0. inversion H0. subst.
        inversion HX as [nx HX'].
        eapply stpd2_sela2.
        eapply indexr_extend_mult. simpl. rewrite E. reflexivity.
        apply beq_nat_true in E. rewrite E. eapply stp2_closed1. eassumption.
        eapply stpd2_trans.
        eexists. eapply stp2_extendH_mult. eapply stp2_extendH_mult. eassumption.
        eapply IHn; try eassumption. omega.
        reflexivity. reflexivity.
        eapply IHn; try eassumption. omega.
        reflexivity. reflexivity.
      * assert (indexr x GH' = Some (GX, TX)) as A. {
          subst.
          eapply indexr_same. apply E. eassumption.
        }
        eapply stpd2_sela2. eapply A. assumption.
        eapply IHn; try eassumption. omega.
        eapply IHn; try eassumption. omega.
    + SCase "selax".
      case_eq (beq_nat x (length GH0)); intros E.
      * assert (indexr x ([(x0, (GX2, TX2))]++GH0) = Some (GX2, TX2)) as A2. {
          simpl. rewrite E. reflexivity.
        }
        assert (indexr x GH = Some (GX2, TX2)) as A2'. {
          rewrite EGH. eapply indexr_extend_mult. apply A2.
        }
        rewrite A2' in H0. inversion H0. subst.
        inversion HX as [nx HX'].
        eapply stpd2_selax.
        eapply indexr_extend_mult. simpl. rewrite E. reflexivity.
      * assert (indexr x GH' = Some (GX, TX)) as A. {
          subst.
          eapply indexr_same. apply E. eassumption.
        }
        eapply stpd2_selax. eapply A.
    + SCase "all".
      assert (length GH = length GH') as A. {
        subst. clear.
        induction GH1.
        - simpl. reflexivity.
        - simpl. simpl in IHGH1. rewrite IHGH1. reflexivity.
      }
      eapply stpd2_all.
      eapply IHn; try eassumption. omega.
      rewrite <- A. assumption. rewrite <- A. assumption.
      rewrite <- A. subst.
      eapply IHn with (GH1:=(0, (G1, T0)) :: GH1); try eassumption. omega.
      simpl. reflexivity. simpl. reflexivity.
      rewrite <- A. subst.
      eapply IHn with (GH1:=(0, (G2, T4)) :: GH1); try eassumption. omega.
      simpl. reflexivity. simpl. reflexivity.
    + SCase "wrapf".
      eapply stpd2_wrapf.
      eapply IHn; try eassumption. omega.
    + SCase "transf".
      eapply stpd2_transf.
      eapply IHn; try eassumption. omega.
      eapply IHn; try eassumption. omega.
Grab Existential Variables.
apply 0. apply 0. apply 0. apply 0.
Qed.

Lemma stpd2_narrow: forall x G1 G2 G3 G4 T1 T2 T3 T4 STO H,
  stpd2 false G1 T1 G2 T2 STO H -> (* careful about H! *)
  stpd2 false G3 T3 G4 T4 STO ((x,(G2,T2))::H) ->
  stpd2 false G3 T3 G4 T4 STO ((x,(G1,T1))::H).
Proof.
  intros. inversion H1 as [n H'].
  eapply (stp2_narrow_aux n) with (GH1:=[]) (GH0:=H). eapply H'. omega.
  simpl. reflexivity. reflexivity.
  assumption.
Qed.


Lemma sstpd2_trans_aux: forall n, forall m G1 G2 G3 T1 T2 T3 STO n1,
  stp2 true m G1 T1 G2 T2 STO nil n1 -> n1 < n ->
  sstpd2 true G2 T2 G3 T3 STO nil ->
  sstpd2 true G1 T1 G3 T3 STO nil.
Proof.
  intros n. induction n; intros; try omega. eu.
  inversion H.
  - Case "topx". subst. inversion H1.
    + SCase "topx". eexists. eauto.
    + SCase "top". eexists. eauto.
    + SCase "sel2". eexists. eapply stp2_strong_sel2. eauto. eauto. eauto. eapply stp2_transf. eauto. eauto.
  - Case "botx". subst. inversion H1.
    + SCase "botx". eexists. eauto.
    + SCase "top". eexists. eauto.
    + SCase "?". eexists. eauto.
    + SCase "sel2". eexists. eapply stp2_strong_sel2. eauto. eauto. eauto. eapply stp2_transf. eauto. eauto.
  - Case "top". subst. inversion H1.
    + SCase "topx". eexists. eauto.
    + SCase "top". eexists. eauto.
    + SCase "sel2". eexists. eapply stp2_strong_sel2. eauto. eauto. eauto. eapply stp2_transf. eauto. eauto.
  - Case "bot". subst.
    apply stp2_reg2 in H1. inversion H1 as [n1' H1'].
    exists (S n1'). apply stp2_bot. apply H1'.
  - Case "bool". subst. inversion H1.
    + SCase "top". eexists. eauto.
    + SCase "bool". eexists. eauto.
    + SCase "sel2". eexists. eapply stp2_strong_sel2. eauto. eauto. eauto. eapply stp2_transf. eauto. eauto.
  - Case "fun". subst. inversion H1.
    + SCase "top".
      assert (stpd2 false G1 T0 G1 T0 STO []) as A0 by solve [eapply stpd2_wrapf; eapply stp2_reg2; eassumption].
      inversion A0 as [na0 HA0].
      assert (stpd2 false G1 T4 G1 T4 STO []) as A4 by solve [eapply stpd2_wrapf; eapply stp2_reg1; eassumption].
      inversion A4 as [na4 HA4].
      eexists. eapply stp2_top. subst. eapply stp2_fun.
      eassumption. eassumption.
    + SCase "fun". subst.
      assert (stpd2 false G3 T7 G1 T0 STO []) as A by solve [eapply stpd2_trans; eauto].
      inversion A as [na A'].
      assert (stpd2 false G1 T4 G3 T8 STO []) as B by solve [eapply stpd2_trans; eauto].
      inversion B as [nb B'].
      eexists. eapply stp2_fun. apply A'. apply B'.
    + SCase "sel2". eexists. eapply stp2_strong_sel2. eauto. eauto. eauto. eapply stp2_transf. eauto. eauto.
  - Case "mem". subst. inversion H1.
    + SCase "top".
      apply stp2_reg1 in H. inversion H. eexists. eapply stp2_top. eassumption.
    + SCase "mem". subst.
      assert (sstpd2 false G3 T7 G1 T0 STO []) as A. {
        eapply sstpd2_trans_axiom; eexists; eauto.
      }
      inversion A as [na A'].
      assert (sstpd2 true G1 T4 G3 T8 STO []) as B. {
        eapply IHn. eassumption. omega. eexists. eassumption.
      }
      inversion B as [nb B'].
      eexists. eapply stp2_mem. apply A'. apply B'.
    + SCase "sel2". eexists. eapply stp2_strong_sel2. eauto. eauto. eauto. eapply stp2_transf. eauto. eauto.
  - Case "cell". subst. inversion H1; subst.
    + SCase "top".
      assert (stpd2 false G1 T0 G1 T0 STO []) as A0 by solve [eapply stpd2_wrapf; eapply stp2_reg1; eassumption].
      inversion A0 as [na0 HA0].
      eexists. eapply stp2_top. eapply stp2_cell. eassumption. eassumption.
    + SCase "cell".
      assert (stpd2 false G3 T2 G1 T0 STO []) as A by solve [eapply stpd2_trans; eauto].
      inversion A as [na A'].
      assert (stpd2 false G1 T0 G3 T2 STO []) as B by solve [eapply stpd2_trans; eauto].
      inversion B as [nb B'].
      eexists. eapply stp2_cell. apply A'. apply B'.
    + SCase "sel2". eexists. eapply stp2_strong_sel2. eauto. eauto. eauto. eapply stp2_transf. eauto. eauto.
  - Case "ssel1".
    assert (sstpd2 true GX TX G3 T3 STO []). eapply IHn. eauto. omega. eexists. eapply H1.
    eu. eexists. eapply stp2_strong_sel1. eauto. eauto. eauto. eauto.
  - Case "ssel2". subst. inversion H1.
    + SCase "top".
      apply stp2_reg1 in H5. inversion H5.
      eexists. eapply stp2_top. eassumption.
    + SCase "ssel1".  (* interesting one *)
      subst. rewrite H7 in H2. inversion H2. subst.
      eapply IHn. eapply H5. omega. eexists. eauto.
    + SCase "ssel2".
      eexists. eapply stp2_strong_sel2. eauto. eauto. eauto. eapply stp2_transf. eauto. eauto.
    + SCase "sselx".
      subst. rewrite H2 in H7. inversion H7. subst.
      eexists. eapply stp2_strong_sel2. eauto. eauto. eauto. eauto.
  - Case "sselx". subst. inversion H1.
    + SCase "top". subst.
      apply stp2_reg1 in H. inversion H.
      eexists. eapply stp2_top. eassumption.
    + SCase "ssel1".
      subst. rewrite H5 in H3. inversion H3. subst.
      eexists. eapply stp2_strong_sel1. eauto. eauto. eauto. eauto.
    + SCase "ssel2". eexists. eapply stp2_strong_sel2. eauto. eauto. eauto. eauto.
    + SCase "sselx".
      subst. rewrite H5 in H3. inversion H3. subst.
      eexists. eapply stp2_strong_selx. eauto. eauto.
  - Case "all". subst. inversion H1.
    + SCase "top".
      apply stp2_reg1 in H. inversion H.
      eexists. eapply stp2_top. eassumption.
    + SCase "ssel2".
      eexists. eapply stp2_strong_sel2. eauto. eauto. eauto. eapply stp2_transf. eauto. eauto.
    + SCase "all".
      subst.
      assert (stpd2 false G3 T7 G1 T0 STO []). eapply stpd2_trans. eauto. eauto.
      assert (stpd2 false G1 (open (TSelH (length ([]:aenv))) T4)
                          G3 (open (TSelH (length ([]:aenv))) T8)
                          STO [(0, (G3, T7))]).
        eapply stpd2_trans. eapply stpd2_narrow. eexists. eapply H9. eauto. eauto.
      repeat eu. eexists. eapply stp2_all. eauto. eauto. eauto. eauto. eapply H8.

  - Case "wrapf". subst. eapply IHn. eapply H2. omega. eexists. eauto.
  - Case "transf". subst. eapply IHn. eapply H2. omega. eapply IHn. eapply H3. omega. eexists. eauto.

Grab Existential Variables.
apply 0. apply 0. apply 0. apply 0. apply 0. apply 0. apply 0.
Qed.

Lemma sstpd2_trans: forall G1 G2 G3 T1 T2 T3 STO,
  sstpd2 true G1 T1 G2 T2 STO nil ->
  sstpd2 true G2 T2 G3 T3 STO nil ->
  sstpd2 true G1 T1 G3 T3 STO nil.
Proof. intros. repeat eu. eapply sstpd2_trans_aux; eauto. eexists. eauto. Qed.


Lemma sstpd2_untrans_aux: forall n, forall G1 G2 T1 T2 STO n1,
  stp2 true false G1 T1 G2 T2 STO nil n1 -> n1 < n ->
  sstpd2 true G1 T1 G2 T2 STO nil.
Proof.
  intros n. induction n; intros; try omega.
  inversion H; subst.
  - Case "wrapf". eexists. eauto.
  - Case "transf". eapply sstpd2_trans_aux. eapply H1. eauto. eapply IHn. eauto. omega.
Qed.

Lemma sstpd2_untrans: forall G1 G2 T1 T2 STO,
  sstpd2 false G1 T1 G2 T2 STO nil ->
  sstpd2 true G1 T1 G2 T2 STO nil.
Proof. intros. repeat eu. eapply sstpd2_untrans_aux; eauto. Qed.



Lemma valtp_widen: forall vf H1 H2 T1 T2 STO,
  val_type STO H1 vf T1 ->
  sstpd2 true H1 T1 H2 T2 STO [] ->
  val_type STO H2 vf T2.
Proof.
  intros vf H1 H2 T1 T2 STO H. revert H2 T2. induction H; intros;
  try (edestruct sstpd2_trans; [(eexists; eauto) | eauto | idtac]);
  try (econstructor; eauto).
Qed.

Lemma restp_widen: forall vf H1 T1 T2 STO,
  res_type STO H1 vf T1 ->
  sstpd2 true H1 T1 H1 T2 STO [] ->
  res_type STO H1 vf T2.
Proof.
  intros. inversion H. eapply not_stuck. eapply valtp_widen; eauto. eauto. 
Qed.

Lemma invert_typ: forall sto venv vx T1 T2,
  val_type sto venv vx (TMem T1 T2) ->
  exists GX TX,
    vx = (vty GX TX) /\
    sstpd2 false venv T1 GX TX sto [] /\
    sstpd2 true GX TX venv T2 sto [].
Proof.
  intros. inversion H; ev; try solve by inversion. inversion H1.
  subst.
  assert (sstpd2 false venv0 T1 venv1 T0 sto []) as E1. {
    eexists. eassumption.
  }
  assert (sstpd2 true venv1 T0 venv0 T2 sto []) as E2. {
    eexists. eassumption.
  }
  repeat eu. repeat eexists; eauto.
Qed.



Lemma stpd2_to_sstpd2_aux: forall n, forall G1 G2 T1 T2 STO m n1,
  stp2 false m G1 T1 G2 T2 STO nil n1 -> n1 < n ->
  sstpd2 m G1 T1 G2 T2 STO nil.
Proof.
  intros n. induction n; intros; try omega.
  inversion H.
  - Case "botx". eexists. eauto.
  - Case "topx". eexists. eauto.
  - Case "top". subst.
    eapply IHn in H1. inversion H1. eexists. eauto. omega.
  - Case "bot". subst.
    eapply IHn in H1. inversion H1. eexists. eauto. omega.
  - Case "bool". eexists. eauto.
  - Case "fun". eexists. eapply stp2_fun. eauto. eauto.
  - Case "mem".
    eapply IHn in H2. eapply sstpd2_untrans in H2. inversion H2.
    eapply IHn in H1. inversion H1.
    eexists. eapply stp2_mem. eauto. eauto. omega. omega.
  - Case "cell". eexists. eapply stp2_cell. eauto. eauto.
  - Case "sel1". subst.
    eapply IHn in H4. eapply sstpd2_untrans in H4. eapply valtp_widen with (2:=H4) in H2.
    remember H2 as Hv. clear HeqHv.
    eapply invert_typ in H2. ev. repeat eu. subst.
    assert (closed 0 (length ([]:aenv)) x1). eapply stp2_closed2; eauto.
    eexists. eapply stp2_strong_sel1. eauto.
    inversion Hv. subst.
    edestruct stp2_reg1. eapply H14.
    eapply v_ty. eassumption. eassumption. eassumption.
    eauto. eauto. omega.
  - Case "sel2".
    eapply IHn in H4. eapply sstpd2_untrans in H4. eapply valtp_widen with (2:=H4) in H2.
    remember H2 as Hv. clear HeqHv.
    eapply invert_typ in H2. ev. repeat eu. subst.
    assert (closed 0 (length ([]:aenv)) x1). eapply stp2_closed2; eauto.
    eexists. eapply stp2_strong_sel2. eauto.
    inversion Hv. subst.
    edestruct stp2_reg1. eapply H13.
    eapply v_ty. eassumption. eassumption. eassumption.
    eauto. eauto. omega.
  - Case "selx".
    eexists. eapply stp2_strong_selx. eauto. eauto.
  - Case "selh1". inversion H1.
  - Case "selh2". inversion H1.
  - Case "selhx". inversion H1.
  - Case "all". eexists. eapply stp2_all. eauto. eauto. eauto. eauto. eauto.
  - Case "wrapf". eapply IHn in H1. eu. eexists. eapply stp2_wrapf. eauto. omega.
  - Case "transf". eapply IHn in H1. eapply IHn in H2. eu. eu. eexists.
    eapply stp2_transf. eauto. eauto. omega. omega.
    Grab Existential Variables.
    apply 0. apply 0. apply 0. apply 0.
Qed.



Lemma stpd2_to_sstpd2: forall G1 G2 T1 T2 STO m,
  stpd2 m G1 T1 G2 T2 STO nil ->
  sstpd2 m G1 T1 G2 T2 STO nil.
Proof. intros. repeat eu. eapply stpd2_to_sstpd2_aux; eauto. Qed.


Lemma stpd2_upgrade: forall G1 G2 T1 T2 STO,
  stpd2 false G1 T1 G2 T2 STO nil ->
  sstpd2 true G1 T1 G2 T2 STO nil.
Proof.
  intros.
  eapply sstpd2_untrans. eapply stpd2_to_sstpd2. eauto.
Qed.

Lemma sstpd2_downgrade_true: forall G1 G2 T1 T2 STO H,
  sstpd2 true G1 T1 G2 T2 STO H ->
  stpd2 true G1 T1 G2 T2 STO H.
Proof.
  intros. inversion H0. induction H1; try solve [eexists; eauto].
  - Case "top".
    destruct m.
    + assert (sstpd2 true G1 T G1 T STO GH) as A. {
        eexists. eassumption.
      }
      specialize (IHstp2 A). inversion IHstp2.
      eexists. eapply stp2_top; eauto.
    + eexists; eauto.
  - Case "bot".
    destruct m.
    + assert (sstpd2 true G2 T G2 T STO GH) as A. {
        eexists. eassumption.
      }
      specialize (IHstp2 A). inversion IHstp2.
      eexists; eauto.
    + eexists; eauto.
  - Case "mem".
    assert (sstpd2 true G1 T2 G2 T4 STO GH) as A. eexists. eassumption.
    specialize (IHstp2_2 A). inversion IHstp2_2.
    assert (sstpd2 false G2 T3 G1 T1 STO GH) as B. eexists. eassumption.
    specialize (IHstp2_1 B). inversion IHstp2_1.
    eexists. eapply stp2_mem2. eauto. eauto.
  - Case "sel1".
    assert (sstpd2 true GX TX G2 T2 STO GH) as A. {
      eexists. eassumption.
    }
    specialize (IHstp2 A). inversion IHstp2.
    assert (stpd2 true GX TX GX TX STO GH) as B. {
      eapply stp2_reg1. eassumption.
    }
    inversion B.
    assert (stpd2 true G2 T2 G2 T2 STO GH) as C. {
      eapply stp2_reg2. eassumption.
    }
    inversion C.
    eexists. eapply stp2_sel1. eassumption. simpl. eassumption. eauto.
    eapply stp2_wrapf. eapply stp2_mem2.
    eapply stp2_wrapf. eapply stp2_bot. simpl. eassumption.
    simpl. eapply stp2_wrapf. eassumption. eassumption.
  - Case "sel2".
    assert (sstpd2 false G1 T1 GX TX STO GH) as A. {
      eexists. eassumption.
    }
    specialize (IHstp2 A). inversion IHstp2.
    assert (stpd2 true GX TX GX TX STO GH) as B. {
      eapply stp2_reg2. eassumption.
    }
    inversion B.
    assert (stpd2 true G1 T1 G1 T1 STO GH) as C. {
      eapply stp2_reg1. eassumption.
    }
    inversion C.
    eexists. eapply stp2_sel2. eassumption. simpl. eassumption. eauto.
    eapply stp2_wrapf. eapply stp2_mem2. eassumption.
    simpl. eapply stp2_wrapf. eapply stp2_top. eassumption. eassumption.
  - Case "wrap". destruct m.
    + eapply stpd2_wrapf. eapply IHstp2. eexists. eassumption.
    + eexists. eapply stp2_wrapf. eassumption.
  - Case "trans". destruct m.
    + eapply stpd2_transf. eapply IHstp2_1. eexists; eauto. eapply IHstp2_2. eexists. eauto.
    + eexists. eapply stp2_transf. eassumption. eassumption.
  Grab Existential Variables.
  apply 0. apply 0. apply 0. apply 0. apply 0. apply 0.
Qed.

Lemma sstpd2_downgrade: forall G1 G2 T1 T2 STO H,
  sstpd2 true G1 T1 G2 T2 STO H ->
  stpd2 false G1 T1 G2 T2 STO H.
Proof.
  intros. apply stpd2_wrapf. apply sstpd2_downgrade_true. assumption.
Qed.


Lemma index_miss {X}: forall x x1 (B:X) A G,
  index x ((x1,B)::G) = A ->
  fresh G <= x1 ->
  x <> x1 ->
  index x G = A.
Proof.
  intros.
  unfold index in H.
  elim (le_xx (fresh G) x1 H0). intros.
  rewrite H2 in H.
  assert (beq_nat x x1 = false). eapply beq_nat_false_iff. eauto.
  rewrite H3 in H. eapply H.
Qed.

Lemma index_hit {X}: forall x x1 (B:X) A G,
  index x ((x1,B)::G) = Some A ->
  fresh G <= x1 ->
  x = x1 ->
  B = A.
Proof.
  intros.
  unfold index in H.
  elim (le_xx (fresh G) x1 H0). intros.
  rewrite H2 in H.
  assert (beq_nat x x1 = true). eapply beq_nat_true_iff. eauto.
  rewrite H3 in H. inversion H. eauto.
Qed.

Lemma index_hit2 {X}: forall x x1 (B:X) A G,
  fresh G <= x1 ->
  x = x1 ->
  B = A ->
  index x ((x1,B)::G) = Some A.
Proof.
  intros.
  unfold index.
  elim (le_xx (fresh G) x1 H). intros.
  rewrite H2.
  assert (beq_nat x x1 = true). eapply beq_nat_true_iff. eauto.
  rewrite H3. rewrite H1. eauto.
Qed.


Lemma indexr_miss {X}: forall x x1 (B:X) A G,
  indexr x ((x1,B)::G) = A ->
  x <> (length G)  ->
  indexr x G = A.
Proof.
  intros.
  unfold indexr in H.
  assert (beq_nat x (length G) = false). eapply beq_nat_false_iff. eauto.
  rewrite H1 in H. eauto.
Qed.

Lemma indexr_hit {X}: forall x x1 (B:X) A G,
  indexr x ((x1,B)::G) = Some A ->
  x = length G ->
  B = A.
Proof.
  intros.
  unfold indexr in H.
  assert (beq_nat x (length G) = true). eapply beq_nat_true_iff. eauto.
  rewrite H1 in H. inversion H. eauto.
Qed.


Lemma indexr_hit0: forall GH (GX0:venv) (TX0:ty),
      indexr 0 (GH ++ [(0,(GX0, TX0))]) =
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


Lemma closed_no_open: forall T x l j,
  closed_rec j l T ->
  T = open_rec j x T.
Proof.
  intros. induction H; intros; eauto;
  try solve [compute; compute in IHclosed_rec; rewrite <-IHclosed_rec; auto];
  try solve [compute; compute in IHclosed_rec1; compute in IHclosed_rec2; rewrite <-IHclosed_rec1; rewrite <-IHclosed_rec2; auto].

  Case "TSelB".
    unfold open_rec. assert (k <> i). omega.
    apply beq_nat_false_iff in H0.
    rewrite H0. auto.
Qed.



Lemma closed_upgrade: forall i j l T,
 closed_rec i l T ->
 j >= i ->
 closed_rec j l T.
Proof.
 intros. generalize dependent j. induction H; intros; eauto.
 Case "TBind". econstructor. eapply IHclosed_rec1. omega. eapply IHclosed_rec2. omega.
 Case "TSelB". econstructor. omega.
Qed.

Lemma closed_upgrade_free: forall i l k T,
 closed_rec i l T ->
 k >= l ->
 closed_rec i k T.
Proof.
 intros. generalize dependent k. induction H; intros; eauto.
 Case "TSelH". econstructor. omega.
Qed.



Lemma open_subst_commute: forall T2 TX (n:nat) x j,
closed j n TX ->
(open_rec j (TSelH x) (subst TX T2)) =
(subst TX (open_rec j (TSelH (x+1)) T2)).
Proof.
  intros T2 TX n. induction T2; intros; eauto.
  - simpl. rewrite IHT2_1. rewrite IHT2_2. eauto. eauto. eauto.
  - simpl. rewrite IHT2_1. rewrite IHT2_2. eauto. eauto. eauto.
  - simpl. rewrite IHT2. eauto. eauto.
  - simpl. case_eq (beq_nat i 0); intros E. symmetry. eapply closed_no_open. eauto. simpl. eauto.
  - simpl. case_eq (beq_nat j i); intros E. simpl.
    assert (x+1<>0). omega. eapply beq_nat_false_iff in H0.
    assert (x=x+1-1). unfold id. omega.
    rewrite H0. eauto.
    simpl. eauto.
  - simpl. rewrite IHT2_1. rewrite IHT2_2. eauto. eapply closed_upgrade. eauto. eauto. eauto.
Qed.




Lemma closed_no_subst: forall T j TX,
   closed_rec j 0 T ->
   subst TX T = T.
Proof.
  intros T. induction T; intros; inversion H; simpl; eauto;
            try rewrite (IHT j TX); eauto; try rewrite (IHT2 (S j) TX); eauto; try rewrite (IHT1 j TX); eauto; try rewrite (IHT2 j TX); eauto.

  eapply closed_upgrade. eauto. eauto.
    eapply closed_upgrade. eauto. eauto.

  subst. omega.
Qed.

Lemma closed_open: forall j n TX T, closed (j+1) n T -> closed j n TX -> closed j n (open_rec j TX T).
Proof.
  intros. generalize dependent j. induction T; intros; inversion H; unfold closed; try econstructor; try eapply IHT1; eauto; try eapply IHT2; eauto; try eapply IHT; eauto. eapply closed_upgrade. eauto. eauto.

  - Case "TSelB". simpl.
    case_eq (beq_nat j i); intros E. eauto.

    econstructor. eapply beq_nat_false_iff in E. omega.

  - eauto.
  - eapply closed_upgrade; eauto.
Qed.


Lemma closed_subst: forall j n TX T, closed j (n+1) T -> closed 0 n TX -> closed j (n) (subst TX T).
Proof.
  intros. generalize dependent j. induction T; intros; inversion H; unfold closed; try econstructor; try eapply IHT1; eauto; try eapply IHT2; eauto; try eapply IHT; eauto.

  - Case "TSelH". simpl.
    case_eq (beq_nat i 0); intros E. eapply closed_upgrade. eapply closed_upgrade_free. eauto. omega. eauto. omega.
    econstructor. assert (i > 0). eapply beq_nat_false_iff in E. omega. omega.
Qed.


Lemma subst_open_commute_m: forall j n m TX T2, closed (j+1) (n+1) T2 -> closed 0 m TX ->
    subst TX (open_rec j (TSelH (n+1)) T2) = open_rec j (TSelH n) (subst TX T2).
Proof.
  intros. generalize dependent j. generalize dependent n.
  induction T2; intros; inversion H; simpl; eauto;
          try rewrite IHT2_1; try rewrite IHT2_2; try rewrite IHT2; eauto.

  - Case "TSelH". simpl. case_eq (beq_nat i 0); intros E.
    eapply closed_no_open. eapply closed_upgrade. eauto. omega.
    eauto.
  - Case "TSelB". simpl. case_eq (beq_nat j i); intros E.
    simpl. case_eq (beq_nat (n+1) 0); intros E2. eapply beq_nat_true_iff in E2. omega.
    assert (n+1-1 = n). omega. eauto.
    eauto.
Qed.

Lemma subst_open_commute: forall j n TX T2, closed (j+1) (n+1) T2 -> closed 0 0 TX ->
    subst TX (open_rec j (TSelH (n+1)) T2) = open_rec j (TSelH n) (subst TX T2).
Proof.
  intros. eapply subst_open_commute_m; eauto.
Qed.

Lemma subst_open_zero: forall j k TX T2, closed k 0 T2 ->
    subst TX (open_rec j (TSelH 0) T2) = open_rec j TX T2.
Proof.
  intros. generalize dependent k. generalize dependent j. induction T2; intros; inversion H; simpl; eauto; try rewrite (IHT2_1 _ k); try rewrite (IHT2_2 _ (S k)); try rewrite (IHT2_2 _ (S k)); try rewrite (IHT2 _ k); eauto.

  eapply closed_upgrade; eauto.
  eapply closed_upgrade; eauto.

  case_eq (beq_nat i 0); intros E. omega. omega.

  case_eq (beq_nat j i); intros E. eauto. eauto.
Qed.



Lemma Forall2_length: forall A B f (G1:list A) (G2:list B),
                        Forall2 f G1 G2 -> length G1 = length G2.
Proof.
  intros. induction H.
  eauto.
  simpl. eauto.
Qed.


Lemma nosubst_intro: forall j T, closed j 0 T -> nosubst T.
Proof.
  intros. generalize dependent j. induction T; intros; inversion H; simpl; eauto.
  omega.
Qed.

Lemma nosubst_open: forall j TX T2, nosubst TX -> nosubst T2 -> nosubst (open_rec j TX T2).
Proof.
  intros. generalize dependent j. induction T2; intros; try inversion H0; simpl; eauto.

  case_eq (beq_nat j i); intros E. eauto. eauto.
Qed.

Lemma nosubst_open_rev: forall j TX T2, nosubst (open_rec j TX T2) -> nosubst TX -> nosubst T2.
Proof.
  intros. generalize dependent j. induction T2; intros; try inversion H; simpl; eauto.
  simpl in H. eauto.
Qed.

Lemma nosubst_zero_closed: forall j T2, nosubst (open_rec j (TSelH 0) T2) -> closed_rec (j+1) 0 T2 -> closed_rec j 0 T2.
Proof.
  intros. generalize dependent j. induction T2; intros; simpl in H; try destruct H; inversion H0; eauto.

  omega.
  econstructor.

  case_eq (beq_nat j i); intros E. rewrite E in H. destruct H. eauto.
  eapply beq_nat_false_iff in E. omega.
Qed.




(* substitution for one-env stp. not necessary, but good sanity check *)

Definition substt (UX: ty) (V: (id*ty)) :=
  match V with
    | (x,T) => (x-1,(subst UX T))
  end.

Lemma indexr_subst: forall GH0 x TX TX',
   indexr x (GH0 ++ [(0, TX)]) = Some (TX') ->
   x = 0 /\ TX = TX' \/
   x > 0 /\ indexr (x-1) (map (substt TX) GH0) = Some (subst TX TX').
Proof.
  intros GH0. induction GH0; intros.
  - simpl in H. case_eq (beq_nat x 0); intros E.
    + rewrite E in H. inversion H.
      left. split. eapply beq_nat_true_iff. eauto. eauto.
    + rewrite E in H. inversion H.
  -  destruct a. unfold id in H. remember ((length (GH0 ++ [(0, TX)]))) as L.
     case_eq (beq_nat x L); intros E.
     + assert (x = L). eapply beq_nat_true_iff. eauto.
       eapply indexr_hit in H.
       right. split. rewrite app_length in HeqL. simpl in HeqL. omega.
       assert ((x - 1) = (length (map (substt TX) GH0))).
       rewrite map_length. rewrite app_length in HeqL. simpl in HeqL. unfold id. omega.
       simpl.
       eapply beq_nat_true_iff in H1. unfold id in H1. unfold id. rewrite H1. subst. eauto. eauto. subst. eauto.
     + assert (x <> L). eapply beq_nat_false_iff. eauto.
       eapply indexr_miss in H. eapply IHGH0 in H.
       inversion H. left. eapply H1.
       right. inversion H1. split. eauto.
       simpl.
       assert ((x - 1) <> (length (map (substt TX) GH0))).
       rewrite app_length in HeqL. simpl in HeqL. rewrite map_length.
       unfold not. intros. subst L. unfold id in H0. unfold id in H2. unfold not in H0. eapply H0. unfold id in H4. rewrite <-H4. omega.
       eapply beq_nat_false_iff in H4. unfold id in H4. unfold id. rewrite H4.
       eauto. subst. eauto.
Qed.


(*
when and how we can replace with multiple environments:

stp2 G1 T1 G2 T2 (GH0 ++ [(0,vtya GX TX)])

1) T1 closed

   stp2 G1 T1 G2' T2' (subst GH0)

2) G1 contains (GX TX) at some index x1

   index x1 G1 = (GX TX)
   stp2 G (subst (TSel x1) T1) G2' T2'

3) G1 = GX <----- valid for Fsub, but not for DOT !

   stp2 G1 (subst TX T1) G2' T2'

4) G1 and GX unrelated

   stp2 ((GX,TX) :: G1) (subst (TSel (length G1)) T1) G2' T2'

*)


(* ---- two-env substitution. first define what 'compatible' types mean. ---- *)


Definition compat (GX:venv) (TX: ty) (V: option vl) (G1:venv) (T1:ty) (T1':ty) :=
  (exists x1 v STO, index x1 G1 = Some v /\ V = Some v /\ GX = GX /\ val_type STO GX v TX /\ T1' = (subst (TSel x1) T1)) \/
  (*  (G1 = GX /\ T1' = (subst TX T1)) \/ *)   (* this is doesn't work for DOT *)
  (* ((forall TA TB, TX <> TMem TA TB) /\ T1' = subst TTop T1) \/ *)(* can remove all term-only bindings -- may not be necessary after all since it applies nosubst *)
  (closed_rec 0 0 T1 /\ T1' = T1) \/ (* this one is for convenience: redundant with next *)
  (nosubst T1 /\ T1' = subst TTop T1).


Definition compat2 (GX:venv) (TX: ty) (V: option vl) (p1:id*(venv*ty)) (p2:id*(venv*ty)) :=
  match p1, p2 with
      (n1,(G1,T1)), (n2,(G2,T2)) => n1=n2(*+1 disregarded*) /\ G1 = G2 /\ compat GX TX V G1 T1 T2
  end.


Lemma closed_compat: forall GX TX V GXX TXX TXX' j k,
  compat GX TX V GXX TXX TXX' ->
  closed 0 k TX ->
  closed j (k+1) TXX ->
  closed j k TXX'.
Proof.
  intros. inversion H;[|destruct H2;[|destruct H2]].
  - destruct H2. destruct H2. destruct H2. destruct H2. destruct H3.
    destruct H3. destruct H4. destruct H4. rewrite H5.
    eapply closed_subst. eauto. eauto.
  - destruct H2. rewrite H3.
    eapply closed_upgrade. eapply closed_upgrade_free. eauto. omega. omega.
  - rewrite H3.
    eapply closed_subst. eauto. eauto.
Qed.

Lemma indexr_compat_miss0: forall GH GH' GX TX V (GXX:venv) (TXX:ty) n,
      Forall2 (compat2 GX TX V) GH GH' ->
      indexr (n+1) (GH ++ [(0,(GX, TX))]) = Some (GXX,TXX) ->
      exists TXX', indexr n GH' = Some (GXX,TXX') /\ compat GX TX V GXX TXX TXX'.
Proof.
  intros. revert n H0. induction H.
  - intros. simpl. eauto. simpl in H0. assert (n+1 <> 0). omega. eapply beq_nat_false_iff in H. rewrite H in H0. inversion H0.
  - intros. simpl. destruct y.
    case_eq (beq_nat n (length l')); intros E.
    + simpl in H1. destruct x. rewrite app_length in H1. simpl in H1.
      assert (n = length l'). eapply beq_nat_true_iff. eauto.
      assert (beq_nat (n+1) (length l + 1) = true). eapply beq_nat_true_iff.
      rewrite (Forall2_length _ _ _ _ _ H0). omega.
      rewrite H3 in H1. destruct p. destruct p0. inversion H1. subst. simpl in H.
      destruct H. destruct H2. subst. inversion H1. subst.
      eexists. eauto.
    + simpl in H1. destruct x.
      assert (n <> length l'). eapply beq_nat_false_iff. eauto.
      assert (beq_nat (n+1) (length l + 1) = false). eapply beq_nat_false_iff.
      rewrite (Forall2_length _ _ _ _ _ H0). omega.
      rewrite app_length in H1. simpl in H1.
      rewrite H3 in H1.
      eapply IHForall2. eapply H1.
Qed.



Lemma compat_top: forall GX TX V G1 T1',
  compat GX TX V G1 TTop T1' -> closed 0 0 TX -> T1' = TTop.
Proof.
  intros ? ? ? ? ? CC CLX. repeat destruct CC as [|CC]; ev; eauto.
Qed.

Lemma compat_bot: forall GX TX V G1 T1',
  compat GX TX V G1 TBot T1' -> closed 0 0 TX -> T1' = TBot.
Proof.
  intros ? ? ? ? ? CC CLX. repeat destruct CC as [|CC]; ev; eauto.
Qed.


Lemma compat_bool: forall GX TX V G1 T1',
  compat GX TX V G1 TBool T1' -> closed 0 0 TX -> T1' = TBool.
Proof.
  intros ? ? ? ? ? CC CLX. repeat destruct CC as [|CC]; ev; eauto.
Qed.

Lemma compat_mem: forall GX TX V G1 T1 T2 T1',
    compat GX TX V G1 (TMem T1 T2) T1' ->
    closed 0 0 TX ->
    exists TA TB, T1' = TMem TA TB /\
                  compat GX TX V G1 T1 TA /\
                  compat GX TX V G1 T2 TB.
Proof.
  intros ? ? ? ? ? ? ? CC CLX. repeat destruct CC as [|CC].
  - ev. repeat eexists; eauto. + left. repeat eexists; eauto. + left. repeat eexists; eauto.
  - ev. repeat eexists; eauto. + right. left. inversion H. eauto. + right. left. inversion H. eauto.
  - ev. repeat eexists; eauto. + right. right. inversion H. eauto. + right. right. inversion H. eauto.
Qed.


Lemma compat_mem_fwd2: forall GX TX V G1 T2 T2',
    compat GX TX V G1 T2 T2' ->
    compat GX TX V G1 (TMem TBot T2) (TMem TBot T2').
Proof.
  intros. repeat destruct H as [|H].
  - ev. repeat eexists; eauto. + left. repeat eexists; eauto. rewrite H3. eauto.
  - ev. repeat eexists; eauto. + right. left. subst. eauto.
  - ev. repeat eexists; eauto. + right. right. subst. simpl. eauto.
Qed.

Lemma compat_mem_fwd1: forall GX TX V G1 T2 T2',
    compat GX TX V G1 T2 T2' ->
    compat GX TX V G1 (TMem T2 TTop) (TMem T2' TTop).
Proof.
  intros. repeat destruct H as [|H].
  - ev. repeat eexists; eauto. + left. repeat eexists; eauto. rewrite H3. eauto.
  - ev. repeat eexists; eauto. + right. left. subst. eauto.
  - ev. repeat eexists; eauto. + right. right. subst. simpl. eauto.
Qed.

Lemma compat_mem_fwdx: forall GX TX V G1 T2 T2',
    compat GX TX V G1 T2 T2' ->
    compat GX TX V G1 (TMem T2 T2) (TMem T2' T2').
Proof.
  intros. repeat destruct H as [|H].
  - ev. repeat eexists; eauto. + left. repeat eexists; eauto. rewrite H3. eauto.
  - ev. repeat eexists; eauto. + right. left. subst. eauto.
  - ev. repeat eexists; eauto. + right. right. subst. simpl. eauto.
Qed.


Lemma compat_fun: forall GX TX V G1 T1 T2 T1',
    compat GX TX V G1 (TFun T1 T2) T1' ->
    closed_rec 0 0 TX ->
    exists TA TB, T1' = TFun TA TB /\
                  compat GX TX V G1 T1 TA /\
                  compat GX TX V G1 T2 TB.
Proof.
  intros ? ? ? ? ? ? ? CC CLX. repeat destruct CC as [|CC].
  - ev. repeat eexists; eauto. + left. repeat eexists; eauto. + left. repeat eexists; eauto.
  - ev. repeat eexists; eauto. + right. left. inversion H. eauto. + right. left. inversion H. eauto.
  - ev. repeat eexists; eauto. + right. right. inversion H. eauto. + right. right. inversion H. eauto.
Qed.


Lemma compat_sel: forall STO GX TX V G1 T1' (GXX:venv) (TXX:ty) x v,
    compat GX TX V G1 (TSel x) T1' ->
    closed 0 0 TX ->
    closed 0 0 TXX ->
    index x G1 = Some v ->
    val_type STO GXX v TXX ->
    exists TXX', T1' = (TSel x) /\ TXX' = TXX /\ compat GX TX V GXX TXX TXX'
.
Proof.
  intros ? ? ? ? ? ? ? ? ? ? CC CL CL1 IX. repeat destruct CC as [|CC].
  - ev. repeat eexists; eauto. + right. left. simpl in H0. eauto.
  - ev. repeat eexists; eauto. + right. left. simpl in H0. eauto.
  - ev. repeat eexists; eauto. + right. left. simpl in H0. eauto.
Qed.



Lemma compat_selh: forall GX TX V G1 T1' GH0 GH0' (GXX:venv) (TXX:ty) x,
    compat GX TX V G1 (TSelH x) T1' ->
    closed 0 0 TX ->
    indexr x (GH0 ++ [(0, (GX, TX))]) = Some (GXX, TXX) ->
    Forall2 (compat2 GX TX V) GH0 GH0' ->
    (x = 0 /\ GXX = GX /\ TXX = TX) \/
    exists TXX',
      x > 0 /\ T1' = TSelH (x-1) /\
      indexr (x-1) GH0' = Some (GXX, TXX') /\
      compat GX TX V GXX TXX TXX'
.
Proof.
  intros ? ? ? ? ? ? ? ? ? ? CC CL IX FA.
  unfold id in x.
  case_eq (beq_nat x 0); intros E.
  - left. assert (x = 0). eapply beq_nat_true_iff. eauto. subst x. rewrite indexr_hit0 in IX. inversion IX. eauto.
  - right. assert (x <> 0). eapply beq_nat_false_iff. eauto.
    assert (x > 0). omega. remember (x-1) as y. assert (x = y+1) as Y. omega. subst x.
    eapply (indexr_compat_miss0 GH0 GH0' _ _ _ _ _ _ FA) in IX.
    repeat destruct CC as [|CC].
    + ev. simpl in H7. rewrite E in H7. rewrite <-Heqy in H7. eexists. eauto.
    + ev. inversion H1. omega.
    + ev. simpl in H4. rewrite E in H4. rewrite <-Heqy in H4. eexists. eauto.
Qed.


Lemma compat_all: forall GX TX V G1 T1 T2 T1' n,
    compat GX TX V G1 (TAll T1 T2) T1' ->
    closed 0 0 TX ->
    closed 1 (n+1) T2 ->
    exists TA TB, T1' = TAll TA TB /\
                  closed 1 n TB /\
                  compat GX TX V G1 T1 TA /\
                  compat GX TX V G1 (open_rec 0 (TSelH (n+1)) T2) (open_rec 0 (TSelH n) TB).
Proof.
  intros ? ? ? ? ? ? ? ? CC CLX CL2. repeat destruct CC as [|CC].

  - ev. simpl in H0. repeat eexists; eauto. eapply closed_subst; eauto.
    + unfold compat. left. repeat eexists; eauto.
    + unfold compat. left. repeat eexists; eauto. rewrite subst_open_commute; eauto.

  - ev. simpl in H0. inversion H. repeat eexists; eauto. eapply closed_upgrade_free; eauto. omega.
    + unfold compat. right. right. split. eapply nosubst_intro; eauto. symmetry. eapply closed_no_subst; eauto.
    + unfold compat. right. right. split.
      * eapply nosubst_open. simpl. omega. eapply nosubst_intro. eauto.
      * rewrite subst_open_commute.  assert (T2 = subst TTop T2) as E. symmetry. eapply closed_no_subst; eauto. rewrite <-E. eauto. eauto. eauto.

  - ev. simpl in H0. destruct H. repeat eexists; eauto. eapply closed_subst; eauto. eauto.
    + unfold compat. right. right. eauto.
    + unfold compat. right. right. split.
      * eapply nosubst_open. simpl. omega. eauto.
      * rewrite subst_open_commute; eauto.
Qed.

Lemma compat_cell: forall GX TX V G1 T1 T1',
    compat GX TX V G1 (TCell T1) T1' ->
    closed_rec 0 0 TX ->
    exists TA, T1' = TCell TA /\
                  compat GX TX V G1 T1 TA.
Proof.
  intros ? ? ? ? ? ? CC CLX. repeat destruct CC as [|CC].
  - ev. repeat eexists; eauto. + left. repeat eexists; eauto.
  - ev. repeat eexists; eauto. + right. left. inversion H. eauto.
  - ev. repeat eexists; eauto. + right. right. simpl in H. eauto.
Qed.

Lemma stp2_substitute_aux: forall n, forall m G1 G2 T1 T2 STO GH n1,
   stp2 false m G1 T1 G2 T2 STO GH n1 ->
   n1 <= n ->
   forall GH0 GH0' GX TX T1' T2' V,
     GH = (GH0 ++ [(0,(GX, TX))]) ->
     val_type STO GX V TX ->
     closed 0 0 TX ->
     compat GX TX (Some V) G1 T1 T1' ->
     compat GX TX (Some V) G2 T2 T2' ->
     Forall2 (compat2 GX TX (Some V)) GH0 GH0' ->
     stpd2 m G1 T1' G2 T2' STO GH0'.
Proof.
  intros n. induction n.
  Case "z". intros. inversion H0. subst. inversion H; eauto.
  intros m G1 G2 T1 T2 STO GH n1 H NE. remember false as flag.
  induction H; inversion Heqflag.
  - Case "topx".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? CX IX1 IX2 FA.
    eapply compat_top in IX1.
    eapply compat_top in IX2.
    subst. eapply stpd2_topx. eauto. eauto.

  - Case "botx".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? CX IX1 IX2 FA.
    eapply compat_bot in IX1.
    eapply compat_bot in IX2.
    subst. eapply stpd2_botx. eauto. eauto.

  - Case "top".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? CX IX1 IX2 FA.
    eapply compat_top in IX2.
    subst. eapply stpd2_top.
    eapply IHn; eauto; omega.
    eauto.

  - Case "bot".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? CX IX1 IX2 FA.
    eapply compat_bot in IX1.
    subst. eapply stpd2_bot.
    eapply IHn; eauto; omega.
    eauto.

  - Case "bool".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? CX IX1 IX2 FA.
    eapply compat_bool in IX1.
    eapply compat_bool in IX2.
    subst. eapply stpd2_bool; eauto. eauto. eauto.

  - Case "fun".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? CX IX1 IX2 FA.
    eapply compat_fun in IX1. repeat destruct IX1 as [? IX1].
    eapply compat_fun in IX2. repeat destruct IX2 as [? IX2].
    subst. eapply stpd2_fun; eapply IHn; eauto; omega.
    eauto. eauto.

  - Case "mem".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? CX IX1 IX2 FA.
    eapply compat_mem in IX1. repeat destruct IX1 as [? IX1].
    eapply compat_mem in IX2. repeat destruct IX2 as [? IX2].
    subst. eapply stpd2_mem; eapply IHn; eauto; omega.
    eauto. eauto.

  - Case "cell".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? CX IX1 IX2 FA.
    eapply compat_cell in IX1. repeat destruct IX1 as [? IX1].
    eapply compat_cell in IX2. repeat destruct IX2 as [? IX2].
    subst. eapply stpd2_cell; eapply IHn; eauto; omega.
    eauto. eauto.

  - Case "sel1".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? CX IX1 IX2 FA.

    assert (length GH = length GH0 + 1). subst GH. eapply app_length.
    assert (length GH0 = length GH0') as EL. eapply Forall2_length. eauto.

    eapply (compat_sel STO GXX TXX (Some V) G1 T1' GX TX) in IX1. repeat destruct IX1 as [? IX1].

    assert (compat GXX TXX (Some V) GX TX TX) as CPX. right. left. eauto.

    subst.
    eapply stpd2_sel1. eauto. eauto. eauto.
    eapply IHn; eauto; try omega.
    eapply compat_mem_fwd2. eauto.
    eapply IHn; eauto; try omega.
    eauto. eauto. eauto. eauto.

  - Case "sel2".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? CX IX1 IX2 FA.

    assert (length GH = length GH0 + 1). subst GH. eapply app_length.
    assert (length GH0 = length GH0') as EL. eapply Forall2_length. eauto.

    eapply (compat_sel STO GXX TXX (Some V) G2 T2' GX TX) in IX2. repeat destruct IX2 as [? IX2].

    assert (compat GXX TXX (Some V) GX TX TX) as CPX. right. left. eauto.

    subst.
    eapply stpd2_sel2. eauto. eauto. eauto.
    eapply IHn; eauto; try omega.
    eapply compat_mem_fwd1. eauto.
    eapply IHn; eauto; try omega.
    eauto. eauto. eauto. eauto.

  - Case "selx".

    intros GH0 GH0' GXX TXX T1' T2' V ? ? CX IX1 IX2 FA.

    assert (length GH = length GH0 + 1). subst GH. eapply app_length.
    assert (length GH0 = length GH0') as EL. eapply Forall2_length. eauto.

    assert (T1' = TSel x1). {
      destruct IX1. ev. eauto. destruct H4. ev. auto. ev. eauto.
    }
    assert (T2' = TSel x2). {
      destruct IX2. ev. eauto. destruct H5. ev. auto. ev. eauto.
    }
    subst.
    eapply stpd2_selx. eauto. eauto.

  - Case "sela1".
    intros GH0 GH0' GXX TXX T1' T2' V ? ? CX IX1 IX2 FA.

    assert (length GH = length GH0 + 1). subst GH. eapply app_length.
    assert (length GH0 = length GH0') as EL. eapply Forall2_length. eauto.

    assert (compat GXX TXX (Some V) G1 (TSelH x) T1') as IXX. eauto.

    eapply (compat_selh GXX TXX (Some V) G1 T1' GH0 GH0' GX TX) in IX1. repeat destruct IX1 as [? IX1].

    destruct IX1.
    + SCase "x = 0".
      repeat destruct IXX as [|IXX]; ev.
      * subst. simpl. inversion H8. subst.
        eapply stpd2_sel1. eauto. eauto. eauto.
        eapply IHn; eauto; try omega. right. left. auto.
        eapply compat_mem_fwd2. eauto.
        eapply IHn; eauto; try omega.
      * subst. inversion H7. omega.
      * subst. destruct H7. eauto.
    + SCase "x > 0".
      ev. subst.
      eapply stpd2_sela1. eauto. eauto.

      assert (x-1+1=x) as A by omega.
      remember (x-1) as x1. rewrite <- A in H0.
      eapply closed_compat. eauto. eapply closed_upgrade_free. eauto. omega. eauto.

      eapply IHn; eauto; try omega. eapply compat_mem_fwd2. eauto.
      eapply IHn; eauto; try omega.
    (* remaining obligations *)
    + eauto. + subst GH. eauto. + eauto.

  - Case "sela2".

    intros GH0 GH0' GXX TXX T1' T2' V ? ? CX IX1 IX2 FA.

    assert (length GH = length GH0 + 1). subst GH. eapply app_length.
    assert (length GH0 = length GH0') as EL. eapply Forall2_length. eauto.

    assert (compat GXX TXX (Some V) G2 (TSelH x) T2') as IXX. eauto.

    eapply (compat_selh GXX TXX (Some V) G2 T2' GH0 GH0' GX TX) in IX2. repeat destruct IX2 as [? IX2].

    destruct IX2.
    + SCase "x = 0".
      repeat destruct IXX as [|IXX]; ev.
      * subst. simpl. inversion H8. subst.
        eapply stpd2_sel2. eauto. eauto. eauto.
        eapply IHn; eauto; try omega. right. left. auto.
        eapply compat_mem_fwd1. eauto.
        eapply IHn; eauto; try omega.
      * subst. inversion H7. omega.
      * subst. destruct H7. eauto.
    + SCase "x > 0".
      ev. subst.
      eapply stpd2_sela2. eauto. eauto.

      assert (x-1+1=x) as A by omega.
      remember (x-1) as x1. rewrite <- A in H0.
      eapply closed_compat. eauto. eapply closed_upgrade_free. eauto. omega. eauto.

      eapply IHn; eauto; try omega. eapply compat_mem_fwd1. eauto.
      eapply IHn; eauto; try omega.
    (* remaining obligations *)
    + eauto. + subst GH. eauto. + eauto.


  - Case "selax".

    intros GH0 GH0' GXX TXX T1' T2' V ? ? CX IX1 IX2 FA.

    assert (length GH = length GH0 + 1). subst GH. eapply app_length.
    assert (length GH0 = length GH0') as EL. eapply Forall2_length. eauto.

    assert (compat GXX TXX (Some V) G1 (TSelH x) T1') as IXX1. eauto.
    assert (compat GXX TXX (Some V) G2 (TSelH x) T2') as IXX2. eauto.

    eapply (compat_selh GXX TXX (Some V) G1 T1' GH0 GH0' GX TX) in IX1. repeat destruct IX1 as [? IX1].
    eapply (compat_selh GXX TXX (Some V) G2 T2' GH0 GH0' GX TX) in IX2. repeat destruct IX2 as [? IX2].
    assert (not (nosubst (TSelH 0))). unfold not. intros. simpl in H1. eauto.
    assert (not (closed 0 0 (TSelH 0))). unfold not. intros. inversion H4. omega.

    destruct x; destruct IX1; ev; try omega; destruct IX2; ev; try omega; subst.
    + SCase "x = 0".
      repeat destruct IXX1 as [IXX1|IXX1]; ev; try contradiction.
      repeat destruct IXX2 as [IXX2|IXX2]; ev; try contradiction.
      * SSCase "sel-sel".
        subst. inversion H14. subst. inversion H6. subst.
        simpl. eapply stpd2_selx. eauto. eauto.
    + SCase "x > 0".
      destruct IXX1; destruct IXX2; ev; subst; eapply stpd2_selax; eauto.
    (* leftovers *)
    + eauto. + subst. eauto. + eauto. + eauto. + subst. eauto. + eauto.

  - Case "all".
    intros GH0 GH0' GX TX T1' T2' V ? ? CX IX1 IX2 FA.

    assert (length GH = length GH0 + 1). subst GH. eapply app_length.
    assert (length GH0 = length GH0') as EL. eapply Forall2_length. eauto.

    eapply compat_all in IX1. repeat destruct IX1 as [? IX1].
    eapply compat_all in IX2. repeat destruct IX2 as [? IX2].

    subst.

    eapply stpd2_all.
    + eapply IHn; eauto; try omega.
    + eauto.
    + eauto.
    + subst.
      eapply IHn with (GH0 := (0, (G1, T1))::GH0); eauto; try omega.
      simpl. reflexivity.
      rewrite app_length. simpl. rewrite EL. eauto.
      rewrite app_length. simpl. rewrite EL. eauto.
      eapply Forall2_cons. simpl. eauto. eauto.
    + subst.
      eapply IHn with (GH0 := (0, (G2, T3))::GH0); eauto; try omega.
      simpl. reflexivity.
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

    (*
       About the middle man in trans:
       We don't know that we can safely remove x.
       However, we can extend G2 without increasing
       the size of the derivations, and obtain the
       necessary compat evidence. This is why, we need
       to do induction on the size n.
     *)

    intros. subst.

    eapply stp2_extend2 with (x:=fresh G2) (v1:=V) in H.
    eapply stp2_extend1 with (x:=fresh G2) (v1:=V) in H0.
    eapply stpd2_transf.
    eapply IHn; eauto; try omega.

    unfold compat. simpl. left. exists (fresh G2). exists V.
    case_eq (le_lt_dec (fresh G2) (fresh G2)); intros LTE LE.
    rewrite <- beq_nat_refl. exists STO.
    split; try split; try split; try split; eauto.
    omega. (* contradiction *)

    eapply IHn; eauto; try omega.
    unfold compat. simpl. left. exists (fresh G2). exists V.
    case_eq (le_lt_dec (fresh G2) (fresh G2)); intros LTE LE.
    rewrite <- beq_nat_refl. exists STO.
    split; try split; try split; try split; eauto.
    omega. (* contradiction *)
    eauto. eauto.

Qed.


Lemma stp2_substitute: forall m G1 G2 T1 T2 STO GH n1,
   stp2 false m G1 T1 G2 T2 STO GH n1 ->
   forall GH0 GH0' GX TX T1' T2' V,
     GH = (GH0 ++ [(0,(GX, TX))]) ->
     val_type STO GX V TX ->
     closed 0 0 TX ->
     compat GX TX (Some V) G1 T1 T1' ->
     compat GX TX (Some V) G2 T2 T2' ->
     Forall2 (compat2 GX TX (Some V)) GH0 GH0' ->
     stpd2 m G1 T1' G2 T2' STO GH0'.
Proof.
  intros. eapply stp2_substitute_aux; eauto.
Qed.

Lemma stpd2_substitute: forall m G1 G2 T1 T2 STO GH,
   stpd2 m G1 T1 G2 T2 STO GH ->
   forall GH0 GH0' GX TX T1' T2' V,
     GH = (GH0 ++ [(0,(GX, TX))]) ->
     val_type STO GX V TX ->
     closed 0 0 TX ->
     compat GX TX (Some V) G1 T1 T1' ->
     compat GX TX (Some V) G2 T2 T2' ->
     Forall2 (compat2 GX TX (Some V)) GH0 GH0' ->
     stpd2 m G1 T1' G2 T2' STO GH0'.
Proof. intros. repeat eu. eapply stp2_substitute; eauto. Qed.


(* --------------------------------- *)

Lemma stp_to_stp2_aux: forall G1 GH T1 T2,
  stp G1 GH T1 T2 ->
  forall STO GX GY, wf_env STO GX G1 -> wf_envh GX GY GH ->
  stpd2 true GX T1 GX T2 STO GY.
Proof with stpd2_wrapf.
  intros G1 G2 T1 T2 ST. induction ST; intros STO GX GY WX WY.
  - Case "topx". eapply stpd2_topx.
  - Case "botx". eapply stpd2_botx.
  - Case "top". eapply stpd2_top.
    specialize (IHST STO GX GY WX WY).
    apply stpd2_reg2 in IHST.
    apply IHST.
  - Case "bot". eapply stpd2_bot.
    specialize (IHST STO GX GY WX WY).
    apply stpd2_reg2 in IHST.
    apply IHST.
  - Case "bool". eapply stpd2_bool; eauto.
  - Case "cell". eapply stpd2_cell; eapply stpd2_wrapf; eauto.
  - Case "fun". eapply stpd2_fun; eapply stpd2_wrapf; eauto.
  - Case "mem". eapply stpd2_mem; eapply stpd2_wrapf; eauto.
  - Case "sel1".
    assert (exists v : vl, index x GX = Some v /\ val_type STO GX v TX) as A.
    eapply index_safe_ex. eauto. eauto.
    destruct A as [? [? VT]].
    eapply stpd2_sel1. eauto. eauto. eapply valtp_closed; eauto.
    eapply stpd2_wrapf. eauto.
    specialize (IHST2 STO GX GY WX WY).
    apply stpd2_reg2 in IHST2.
    apply IHST2.
  - Case "sel2".
    assert (exists v : vl, index x GX = Some v /\ val_type STO GX v TX) as A.
    eapply index_safe_ex. eauto. eauto.
    destruct A as [? [? VT]].
    eapply stpd2_sel2. eauto. eauto. eapply valtp_closed; eauto.
    eapply stpd2_wrapf. eauto.
    specialize (IHST2 STO GX GY WX WY).
    apply stpd2_reg2 in IHST2.
    apply IHST2.
  - Case "selx".
    assert (exists v : vl, index x GX = Some v /\ val_type STO GX v TX) as A.
    eapply index_safe_ex. eauto. eauto. ev.
    eapply stpd2_selx. eauto. eauto.
  - Case "sela1". eauto.
    assert (exists v, indexr x GY = Some v /\ valh_type GX GY v TX) as A.
    eapply index_safeh_ex. eauto. eauto. eauto.
    destruct A as [? [? VT]]. destruct x0.
    inversion VT. subst.
    eapply stpd2_sela1. eauto. eauto.
    eapply stpd2_wrapf. eapply IHST1. eauto. eauto.
    specialize (IHST2 _ _ _ WX WY).
    apply stpd2_reg2 in IHST2.
    apply IHST2.
  - Case "sela2".
    assert (exists v, indexr x GY = Some v /\ valh_type GX GY v TX) as A.
    eapply index_safeh_ex. eauto. eauto. eauto.
    destruct A as [? [? VT]]. destruct x0.
    inversion VT. subst.
    eapply stpd2_sela2. eauto. eauto.
    eapply stpd2_wrapf. eapply IHST1. eauto. eauto.
    specialize (IHST2 _ _ _ WX WY).
    apply stpd2_reg2 in IHST2.
    apply IHST2.
  - Case "selax". eauto.
    assert (exists v, indexr x GY = Some v /\ valh_type GX GY v TX) as A.
    eapply index_safeh_ex. eauto. eauto. eauto. ev. destruct x0.
    eapply stpd2_selax. eauto.
  - Case "all".
    subst x. assert (length GY = length GH). eapply wfh_length; eauto.
    eapply stpd2_all. eapply stpd2_wrapf. eauto. rewrite H. eauto. rewrite H.  eauto.
    rewrite H.
    eapply stpd2_wrapf. eapply IHST2. eauto. eapply wfeh_cons. eauto.
    rewrite H.
    eapply stpd2_wrapf. eapply IHST3; eauto. apply wfeh_cons. assumption.
Qed.

Lemma stp_to_stp2: forall G1 STO GH T1 T2,
  stp G1 GH T1 T2 ->
  forall GX GY, wf_env STO GX G1 -> wf_envh GX GY GH ->
  stpd2 false GX T1 GX T2 STO GY.
Proof.
  intros. eapply stpd2_wrapf. eapply stp_to_stp2_aux; eauto.
Qed.



Lemma invert_abs: forall sto venv vf T1 T2,
  val_type sto venv vf (TFun T1 T2) ->
  exists env tenv f x y T3 T4,
    vf = (vabs env f x y) /\
    fresh env <= f /\
    1 + f <= x /\
    wf_env sto env tenv /\
    has_type ((x,T3)::(f,TFun T3 T4)::tenv) y T4 /\
    sstpd2 true venv T1 env T3 sto [] /\
    sstpd2 true env T4 venv T2 sto [].
Proof.
  intros. inversion H; repeat ev; try solve by inversion. inversion H4.
  assert (stpd2 false venv0 T1 venv1 T0 sto []) as E1. eauto.
  assert (stpd2 false venv1 T3 venv0 T2 sto []) as E2. eauto.
  eapply stpd2_upgrade in E1. eapply stpd2_upgrade in E2.
  repeat eu. repeat eexists; eauto.
Qed.





Lemma invert_tabs: forall sto venv vf vx T1 T2,
  val_type sto venv vf (TAll T1 T2) ->
  val_type sto venv vx T1 ->
  sstpd2 true venv T2 venv T2 sto [] ->
  exists env tenv x y T3 T4,
    vf = (vtabs env x T3 y) /\
    fresh env = x /\
    wf_env sto env tenv /\
    has_type ((x,T3)::tenv) y (open (TSel x) T4) /\
    sstpd2 true venv T1 env T3 sto [] /\
    sstpd2 true ((x,vx)::env) (open (TSel x) T4) venv T2 sto []. (* (open T1 T2) []. *)
Proof.
  intros sto venv0 vf vx T1 T2 VF VX STY. inversion VF; ev; try solve by inversion. inversion H2. subst.
  eexists. eexists. eexists. eexists. eexists. eexists.
  repeat split; eauto.
  remember (fresh venv1) as x.
  remember (x + fresh venv0) as xx.

  eapply stpd2_upgrade; eauto.

  (* -- new goal: result -- *)

  (* inversion of TAll < TAll *)
  assert (stpd2 false venv0 T1 venv1 T0 sto []) as ARG. eauto.
  assert (stpd2 false venv1 (open (TSelH 0) T3) venv0 (open (TSelH 0) T2) sto [(0,(venv0, T1))]) as KEY. {
    eauto.
  }
  eapply stpd2_upgrade in ARG.

  (* need reflexivity *)
  assert (stpd2 false venv0 T1 venv0 T1 sto []). eapply stpd2_wrapf. eapply stpd2_reg1. eauto.
  assert (closed 0 0 T1). eapply stpd2_closed1 in H1. simpl in H1. eauto.

  (* now rename *)

  assert (stpd2 false ((fresh venv1,vx) :: venv1) (open_rec 0 (TSel (fresh venv1)) T3) venv0 (T2) sto []). { (* T2 was open T1 T2 *)

    (* now that sela1/sela2 can use subtyping, it is better to dispatch on the
       valtp evidence (instead of the type, as before) *)

    (* eapply inv_vtp_half in VX. ev. *)

    assert (closed 0 (length ([]:aenv)) T2). eapply sstpd2_closed1; eauto.
    assert (open (TSelH 0) T2 = T2) as OP2. symmetry. eapply closed_no_open; eauto.


    eapply stpd2_substitute with (GH0:=nil).
    eapply stpd2_extend1. eapply KEY. (* previously: stpd2_narrow. inv_vtp_half. eapply KEY. *)
    eauto. simpl. eauto.
    eapply VX. eassumption.
    left. repeat eexists. eapply index_hit2. eauto. eauto. eauto. eauto.
    rewrite (subst_open_zero 0 1). eauto. eauto.
    right. left. split. rewrite OP2. eauto. eauto. eauto.
  }
  eapply stpd2_upgrade in H4.

  (* done *)
  subst. eauto.
Qed.

Lemma val_wf_sto_ext:
  (forall senv venv env, wf_env senv venv env ->
     forall senv', wf_env (senv' ++ senv) venv env) /\
  (forall senv G v T, val_type senv G v T ->
     forall senv', val_type (senv' ++ senv) G v T).
Proof.
  apply (proj2 stp2_val_wf_sto_ext).
Qed.

Lemma wf_env_sto_ext: forall senv' senv venv env,
  wf_env senv venv env ->
  wf_env (senv'++senv) venv env.
Proof.
  intros. generalize senv'. apply (proj1 val_wf_sto_ext). assumption.
Qed.

Lemma valtp_sto_ext: forall senv' senv G v T,
  val_type senv G v T ->
  val_type (senv'++senv) G v T.
Proof.
  intros. generalize senv'. apply (proj2 val_wf_sto_ext). assumption.
Qed.


Lemma wf_sto_sto_ext: forall senv' senv venv env,
  wf_sto senv venv env ->
  wf_sto (senv'++senv) venv env.
Proof.
  intros. induction H.
  - apply wfs_nil.
  - apply wfs_cons. apply valtp_sto_ext. assumption. assumption.
Qed.

Lemma wfs_length : forall sto vs ts,
                    wf_sto sto vs ts ->
                    (length vs = length ts).
Proof.
  intros. induction H. auto.
  compute. eauto.
Qed.

Lemma valtp_reg: forall STO G v T,
                   val_type STO G v T ->
                   sstpd2 true G T G T STO [].
Proof. intros. induction H; eapply stp2_reg2; eauto. Qed.

Lemma invert_loc: forall sto venv vx T,
  val_type sto venv vx (TCell T) ->
  exists i venvi Ti,
    vx = (vloc i) /\
    indexr i sto = Some (venvi,Ti) /\
    sstpd2 true venv T venvi Ti sto [] /\
    sstpd2 true venvi Ti venv T sto [].
Proof.
  intros. inversion H; ev; try solve by inversion. inversion H1.
  subst.
  assert (sstpd2 true venv0 T venv2 T1 sto []) as E1. {
    eapply stpd2_upgrade. eexists. eassumption.
  }
  assert (sstpd2 true venv2 T1 venv0 T sto []) as E2. {
    eapply stpd2_upgrade. eexists. eassumption.
  }
  repeat eu. repeat eexists; eauto.
Qed.

Lemma index_sto_safe_ex: forall G sto senv venv i T,
             wf_sto G sto senv ->
             indexr i senv = Some (venv,T) ->
             exists v, indexr i sto = Some v /\ val_type G venv v T.
Proof. intros. induction H.
   - Case "nil". inversion H0.
   - Case "cons". inversion H0.
     case_eq (beq_nat i (length ts)); intros E2.
     * SSCase "hit".
       rewrite E2 in H3. inversion H3. subst. clear H3.
       assert (length ts = length vs) as A. { symmetry. eapply wfs_length. eauto. }
       simpl. rewrite A in E2. rewrite E2.
       eexists. split. eauto. assumption.
     * SSCase "miss".
       rewrite E2 in H3.
       assert (exists v, indexr i vs = Some v /\ val_type G venv0 v T) as A by eauto.
       destruct A as [? A]. destruct A as [A1 A2].
       eexists. split. eapply indexr_extend. eauto.
       assumption.
Qed.

Lemma update_sto_safe_ex: forall G sto senv venv i T v,
             wf_sto G sto senv ->
             indexr i senv = Some (venv,T) ->
             val_type G venv v T ->
             wf_sto G (update i (0,v) sto) senv.
Proof. intros. induction H.
   - Case "nil". inversion H0.
   - Case "cons". inversion H0. simpl.
     case_eq (beq_nat i (length ts)); intros E2.
     * SSCase "hit".
       rewrite E2 in H4. inversion H4. subst. clear H4.
       assert (length ts = length vs) as A. { symmetry. eapply wfs_length. eauto. }
       simpl. rewrite A in E2. unfold id in E2. rewrite E2.
       apply wfs_cons. assumption. assumption.
     * SSCase "miss".
       rewrite E2 in H4.
       assert (length ts = length vs) as A. { symmetry. eapply wfs_length. eauto. }
       simpl. rewrite A in E2. unfold id in E2. rewrite E2.
       apply wfs_cons. assumption. apply IHwf_sto. assumption. assumption.
Qed.

(* if not a timeout, then result not stuck and well-typed *)

Theorem full_safety : forall n e senv sto tenv venv res T,
  teval n sto venv e = Some res ->
  has_type tenv e T ->
  wf_env senv venv tenv ->
  wf_sto senv sto senv ->
  exists senv', res_type (senv'++senv) venv res T.

Proof.
  intros n. induction n.
  (* 0 *)   intros. inversion H.
  (* S n *) intros. destruct e; inversion H.

  - Case "True".
    remember (ttrue) as e. induction H0; inversion Heqe; subst.
    + exists nil. rewrite app_nil_l.
      eapply not_stuck. eapply v_bool; eauto. assumption.
    + assert (
          exists senv',
            res_type (senv' ++ senv) venv0 (Some (sto, vbool true)) T1) as A. {
        eapply IHhas_type; eauto.
      }
      destruct A as [senv' A].
      exists senv'. eapply restp_widen. eapply A. eapply stpd2_upgrade. eapply stp_to_stp2; eauto. eapply wf_env_sto_ext; eauto. econstructor.

  - Case "False".
    remember (tfalse) as e. induction H0; inversion Heqe; subst.
    + exists nil. rewrite app_nil_l.
      eapply not_stuck. eapply v_bool; eauto. assumption.
    + assert (
          exists senv',
            res_type (senv' ++ senv) venv0 (Some (sto, vbool false)) T1) as A. {
        eapply IHhas_type; eauto.
      }
      destruct A as [senv' A].
      exists senv'. eapply restp_widen. eapply A. eapply stpd2_upgrade. eapply stp_to_stp2; eauto. eapply wf_env_sto_ext; eauto. econstructor.

  - Case "Var".
    remember (tvar i) as e. induction H0; inversion Heqe; subst.
    + exists nil. rewrite app_nil_l.
      destruct (index_safe_ex senv venv0 env T1 i) as [v [I V]]; eauto.
      rewrite I. eapply not_stuck. eapply V.
      assumption.
    + assert (
         exists senv',
                 res_type (senv' ++ senv) venv0
                   match index i venv0 with
                   | Some v => Some (sto, v)
                   | None => None
                   end T1) as A. {
        eapply IHhas_type; eauto.
      }
      destruct A as [senv' A].
      exists senv'. eapply restp_widen. eapply A. eapply stpd2_upgrade. eapply stp_to_stp2; eauto. eapply wf_env_sto_ext; eauto. econstructor.

  - Case "New".
    remember (tnew e) as e'. induction H0; inversion Heqe'; subst.
    +
      remember (teval n sto venv0 e) as te.

      destruct te as [re|]; try solve by inversion.
      assert (exists senv', res_type (senv'++senv) venv0 re T1) as HRE. SCase "HRE". subst. eapply IHn; eauto.
      destruct HRE as [senve' HRE].
      inversion HRE as [? ? ? ve]. subst.
      inversion H4. subst.
      exists ([(0, (venv0,T1))]++senve').
      inversion HRE; subst.
      eapply valtp_reg in H5. eapply sstpd2_downgrade in H5. destruct H5 as [? H5].
      assert (stpd2 false venv0 T1 venv0 T1 senv []) as A. {
        eapply stp_to_stp2. eassumption. eauto. apply wfeh_nil.
      }
      destruct A as [? A].
      eapply not_stuck.
      eapply v_loc.
      unfold indexr. simpl.
      rewrite <- (wfs_length (senve'++senv) sto0 (senve'++senv)). 
      rewrite <- beq_nat_refl. reflexivity. assumption.
      eapply stp2_cell. eapply stp2_extendS_mult. eapply A. eapply stp2_extendS_mult. eapply A.
      econstructor. eapply valtp_widen. rewrite <- app_assoc. eapply valtp_sto_ext. eassumption.
      eapply stpd2_upgrade. eexists. eapply stp2_extendS_mult. eapply A.
      rewrite <- app_assoc. eapply wf_sto_sto_ext. eauto.

    + assert (
          exists senv', res_type (senv' ++ senv) venv0 res T1
        ) as A. {
        eapply IHhas_type; eauto.
      }
      destruct A as [senv' A].
      exists senv'. eapply restp_widen. eapply A. eapply stpd2_upgrade. eapply stp_to_stp2; eauto. eapply wf_env_sto_ext; eauto. econstructor.

  - Case "Get".
    remember (tget e) as e'. induction H0; inversion Heqe'; subst.
    +
      remember (teval n sto venv0 e) as te.
      destruct te as [re|]; try solve by inversion.
      assert (exists senv', res_type (senv'++senv) venv0 re (TCell T1)) as HRE. SCase "HRE". subst. eapply IHn; eauto.
      destruct HRE as [senve' HRE].
      inversion HRE as [? ? ? ve]. subst.

      destruct (invert_loc (senve' ++ senv) venv0 ve T1) as
          [i [venvi [Ti [EB [ET [B1 B2]]]]]]. eauto.

      subst.

      destruct (index_sto_safe_ex (senve'++senv) sto0 (senve'++senv) venvi i Ti) as [v [A1 A2]];
        eauto.
      rewrite A1 in H4. inversion H4. subst.

      exists senve'. eapply not_stuck. eapply valtp_widen. eassumption. assumption.
      assumption.

    + assert (exists senv', res_type (senv' ++ senv) venv0 res T1) as A. {
        eapply IHhas_type; eauto.
      }
      destruct A as [senv' A].
      exists senv'. eapply restp_widen. eapply A. eapply stpd2_upgrade. eapply stp_to_stp2; eauto. eapply wf_env_sto_ext; eauto. econstructor.

  - Case "Set".
    remember (tset e1 e2) as e. induction H0; inversion Heqe; subst.

    +
      remember (teval n sto venv0 e1) as te1.

      destruct te1 as [re1|]; try solve by inversion.
      assert (exists senv', res_type (senv'++senv) venv0 re1 (TCell T1)) as HRE1. subst. eapply IHn; eauto.
      destruct HRE1 as [senv1' HRE1].
      inversion HRE1 as [? ? ? ve1].

      subst.

      destruct (invert_loc (senv1' ++ senv) venv0 ve1 T1) as
          [i [venvi [Ti [EB [ET [B1 B2]]]]]]. eauto.

      subst.

      remember (teval n sto0 venv0 e2) as te2.

      destruct te2 as [re2|]; try solve by inversion.
      assert (exists senv', res_type (senv'++senv1'++senv) venv0 re2 T1) as HRE2. subst. eapply IHn; eauto. eapply wf_env_sto_ext. assumption.
      destruct HRE2 as [senv2' HRE2].
      inversion HRE2 as [? ? ? ve2].

      subst. inversion H4. subst.

      exists (senv2'++senv1'). rewrite <- app_assoc.
      eapply not_stuck. assumption. eapply update_sto_safe_ex. assumption.
      eapply indexr_extend_mult. eassumption.
      eapply valtp_widen. eassumption. eapply sstpd2_extendS_mult. assumption.
      
    + assert (exists senv', res_type (senv' ++ senv) venv0 res T1) as A. {
        eapply IHhas_type; eauto.
      }
      destruct A as [senv' A].
      exists senv'. eapply restp_widen. eapply A. eapply stpd2_upgrade. eapply stp_to_stp2; eauto. eapply wf_env_sto_ext; eauto. econstructor.

  - Case "Typ".
    remember (ttyp t) as e. induction H0; inversion Heqe; subst.
    + exists nil. rewrite app_nil_l. eapply not_stuck.
      assert (exists n0, stp2 true true venv0 (TMem t t) venv0 (TMem t t) senv [] n0) as A. {
        eapply stpd2_upgrade. eapply stp_to_stp2; eauto. econstructor.
     }
     destruct A as [? A].                                                                    eapply v_ty; eauto. eassumption.
    + assert (
          exists senv',
            res_type (senv' ++ senv) venv0 (Some (sto, vty venv0 t)) T1) as A. {
        eapply IHhas_type; eauto.
      }
      destruct A as [senv' A].
      exists senv'. eapply restp_widen. eapply A. eapply stpd2_upgrade. eapply stp_to_stp2; eauto. eapply wf_env_sto_ext; eauto. econstructor.

  - Case "App".
    remember (tapp e1 e2) as e. induction H0; inversion Heqe; subst.
    +
      remember (teval n sto venv0 e2) as tx.

      destruct tx as [rx|]; try solve by inversion.
      assert (exists senv', res_type (senv'++senv) venv0 rx T1) as HRX. SCase "HRX". subst. eapply IHn; eauto.
      destruct HRX as [senvx' HRX].
      inversion HRX as [? ? ? vx].

      subst rx.
      remember (teval n sto0 venv0 e1) as tf.

      destruct tf as [rf|]; try solve by inversion.
      assert (exists senv', res_type (senv'++(senvx'++senv)) venv0 rf (TFun T1 T2)) as HRF. SCase "HRF". subst. eapply IHn; eauto. apply wf_env_sto_ext. assumption.
      destruct HRF as [senvf' HRF].
      inversion HRF as [? ? ? vf].

      destruct (invert_abs (senvf'++senvx'++senv) venv0 vf T1 T2) as
          [env1 [tenv [f0 [x0 [y0 [T3 [T4 [EF [FRF [FRX [WF [HTY [STX STY]]]]]]]]]]]]]. eauto.
      (* now we know it's a closure, and we have has_type evidence *)

      assert (exists senv', res_type (senv'++senvf'++senvx'++senv) ((x0,vx)::(f0,vf)::env1) res T4) as HRY.
        SCase "HRY".
          subst. eapply IHn. eauto. eauto.
          (* wf_env f x *) econstructor. eapply valtp_widen. eapply valtp_sto_ext. eauto. eapply sstpd2_extend2. eapply sstpd2_extend2. eauto. eauto. eauto.
          (* wf_env f   *)
          eapply sstpd2_downgrade in STX. eapply sstpd2_downgrade in STY. repeat eu.
          assert (stpd2 false env1 T3 env1 T3 (senvf' ++ senvx' ++ senv) []) as A3. {
            eapply stpd2_wrapf. eapply stpd2_reg2. eauto.
          }
          inversion A3 as [na3 HA3].
          assert (stpd2 false env1 T4 env1 T4 (senvf' ++ senvx' ++ senv) []) as A4 by solve [eapply stpd2_wrapf; eapply stpd2_reg1; eauto].
          inversion A4 as [na4 HA4].
          econstructor. eapply v_abs; eauto. eapply stp2_extend2.
          eapply stp2_fun. eassumption. eassumption. eauto. eauto. eauto.

      destruct HRY as [senv' HRY].
      inversion HRY as [? vy].

      exists (senv'++senvf'++senvx'). rewrite <- app_assoc. rewrite <- app_assoc.
      eapply not_stuck. eapply valtp_widen; eauto. eapply sstpd2_extend1. eapply sstpd2_extend1. eapply sstpd2_extendS_mult. eauto. eauto. eauto. eauto.

    + assert (
          exists senv',
            res_type (senv' ++ senv) venv0 res T1) as A. {
        eapply IHhas_type; eauto.
      }
      destruct A as [senv' A].
      exists senv'. eapply restp_widen. eapply A. eapply stpd2_upgrade. eapply stp_to_stp2; eauto. eapply wf_env_sto_ext; eauto. econstructor.


  - Case "Abs".
    remember (tabs i i0 e) as xe. induction H0; inversion Heqxe; subst.
    + exists nil. rewrite app_nil_l. eapply not_stuck.
      assert (exists n0, stp2 true true venv0 (TFun T1 T2) venv0 (TFun T1 T2) senv [] n0) as A. {
        eapply stpd2_upgrade. eapply stp_to_stp2. eauto. eauto. econstructor.
      }
      destruct A as [? A].
      eapply v_abs; eauto. rewrite (wf_fresh senv venv0 env H1). eauto. assumption.
    + assert (
          exists senv',
            res_type (senv' ++ senv) venv0 (Some (sto, vabs venv0 i i0 e)) T1) as A. {
        eapply IHhas_type; eauto.
      }
      destruct A as [senv' A].
      exists senv'. eapply restp_widen. eapply A. eapply stpd2_upgrade. eapply stp_to_stp2; eauto. eapply wf_env_sto_ext; eauto. econstructor.

  - Case "TApp".
    remember (ttapp e1 e2) as e. induction H0; inversion Heqe; subst.
    +
      remember (teval n sto venv0 e2) as tx.

      destruct tx as [rx|]; try solve by inversion.
      assert (exists senv', res_type (senv'++senv) venv0 rx T11) as HRX. SCase "HRX". subst. eapply IHn; eauto.
      destruct HRX as [senvx' HRX].
      inversion HRX as [? ? ? vx].

      subst rx.
      remember (teval n sto0 venv0 e1) as tf.

      destruct tf as [rf|]; try solve by inversion.
      assert (exists senv', res_type (senv'++(senvx'++senv)) venv0 rf (TAll T11 T12)) as HRF. SCase "HRF". subst. eapply IHn; eauto. apply wf_env_sto_ext. assumption.
      destruct HRF as [senvf' HRF].
      inversion HRF as [? ? ? vf].

      destruct (invert_tabs (senvf'++senvx'++senv) venv0 vf vx T11 T12) as
          [env1 [tenv [x0 [y0 [T3 [T4 [EF [FRX [WF [HTY [STX STY]]]]]]]]]]].
      eauto. eapply valtp_sto_ext. eauto. eapply stpd2_upgrade. eapply stp_to_stp2; eauto. eapply wf_env_sto_ext; eauto. eapply wf_env_sto_ext. eauto. econstructor.
      (* now we know it's a closure, and we have has_type evidence *)

      assert (exists senv', res_type (senv'++senvf'++senvx'++senv) ((x0,vx)::env1) res (open (TSel x0) T4)) as HRY.
        SCase "HRY".
          subst. eapply IHn. eauto. eauto.
          (* wf_env x *) econstructor. eapply valtp_widen. eapply valtp_sto_ext. eauto. eapply sstpd2_extend2. eauto. eauto. eauto. eauto.
      destruct HRY as [senv' HRY].
      inversion HRY as [? vy].

      exists (senv'++senvf'++senvx'). rewrite <- app_assoc. rewrite <- app_assoc.
      eapply not_stuck. eapply valtp_widen; eauto. eapply sstpd2_extendS_mult. eauto. eauto. 

    + assert (exists senv', res_type (senv' ++ senv) venv0 res T1) as A. {
        eapply IHhas_type; eauto.
      }
      destruct A as [senv' A].
      exists senv'. eapply restp_widen. eapply A. eapply stpd2_upgrade. eapply stp_to_stp2; eauto. eapply wf_env_sto_ext; eauto. econstructor.

  - Case "TAbs".
    remember (ttabs i t e) as xe. induction H0; inversion Heqxe; subst.
    + exists nil. rewrite app_nil_l. eapply not_stuck.
      assert (exists n0, stp2 true true venv0 (TAll t T2) venv0 (TAll t T2) senv [] n0) as A. {
        eapply stpd2_upgrade. eapply stp_to_stp2. eauto. eauto. econstructor.
      }
      destruct A as [? A].
      eapply v_tabs; eauto. subst i. eauto. rewrite (wf_fresh senv venv0 env H1). eauto. assumption.
    + assert (exists senv',
                res_type (senv' ++ senv) venv0
                         (Some (sto, vtabs venv0 i t e)) T1) as A. {
        eapply IHhas_type; eauto.
      }
      destruct A as [senv' A].
      exists senv'. eapply restp_widen. eapply A. eapply stpd2_upgrade. eapply stp_to_stp2; eauto. eapply wf_env_sto_ext; eauto. econstructor.

       Grab Existential Variables. apply 0. apply 0.
Qed.

End FSUB.
