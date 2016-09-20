(*
STLC
T ::= Bool | T -> T 
t ::= true | false | x | lambda x:T.t | t t
*)

(* Semantic equality big-step env / big-step subst / small-step *)

Require Export SfLib.

Require Export Arith.EqNat.
Require Export Arith.Le.
Require Import Coq.Program.Equality.

(* ### Syntax ### *)

Definition id := nat.

Inductive ty : Type :=
| TTop  : ty
| TBool : ty           
| TFun  : ty -> ty -> ty
.

Inductive tm : Type :=
| ttrue : tm
| tfalse : tm
| tvar : id -> tm
| tabs : ty -> tm -> tm
| tapp : tm -> tm -> tm
.

Inductive vl : Type :=
| vbool : bool -> vl
(* a closure for a term abstraction *)
| vabs : venv (*H*) -> ty -> tm -> vl
with venv : Type := (* need to recurse structurally, hence don't use built-in list *)
| vnil: venv
| vcons: vl -> venv -> venv
.

Definition tenv := list (@ty). (* Gamma environment: static *)
(*Definition venv := list vl. (* H environment: run-time *) *)

(* ### Representation of Bindings ### *)

(* An environment is a list of values, indexed by decrementing ids. *)

Fixpoint lengthr (l : venv) : nat :=
  match l with
    | vnil => 0
    | vcons a  l' =>
      S (lengthr l')
  end.


Fixpoint indexr (n : id) (l : venv) : option vl :=
  match l with
    | vnil => None
    | vcons a  l' =>
      if (beq_nat n (lengthr l')) then Some a else indexr n l'
  end.



(* ### Evaluation (Big-Step Semantics) ### *)

(*
None             means timeout
Some None        means stuck
Some (Some v))   means result v
*)

(* Environment-based evaluator *)

Fixpoint teval(n: nat)(env: venv)(t: tm){struct n}: option (option vl) :=
  match n with
    | 0 => None
    | S n =>
      match t with
        | ttrue        => Some (Some (vbool true))
        | tfalse       => Some (Some (vbool false))
        | tvar x       => Some (indexr x env)
        | tabs T y     => Some (Some (vabs env T y))
        | tapp ef ex   =>
          match teval n env ex with
            | None => None
            | Some None => Some None
            | Some (Some vx) =>
              match teval n env ef with
                | None => None
                | Some None => Some None
                | Some (Some (vbool _)) => Some None
                | Some (Some (vabs env2 _ ey)) =>
                  teval n (vcons vx env2) ey
              end
          end
      end
  end.


(* Substitution-based evaluator *)

Fixpoint shift_tm (u:nat) (T : tm) {struct T} : tm :=
  match T with
    | ttrue       => ttrue
    | tfalse      => tfalse
    | tvar i      => tvar (i + u)
    | tabs T1 t   => tabs T1 (shift_tm u t)
    | tapp t1 t2  => tapp (shift_tm u t1) (shift_tm u t2)
  end.

Fixpoint subst_tm (u:tm) (T : tm) {struct T} : tm :=
  match T with
    | ttrue       => ttrue
    | tfalse      => tfalse
    | tvar i      => if beq_nat i 0 then u else tvar (i-1)
    | tabs T1 t   => tabs T1 (subst_tm (shift_tm 1 u) t)
    | tapp t1 t2  => tapp (subst_tm u t1) (subst_tm u t2)
  end.

Fixpoint tevals(n: nat)(t: tm){struct n}: option (option tm) :=
  match n with
    | 0 => None
    | S n =>
      match t with
        | ttrue        => Some (Some ttrue)
        | tfalse       => Some (Some tfalse)
        | tvar x       => Some None
        | tabs T y     => Some (Some (tabs T y))
        | tapp ef ex   =>
          match tevals n ex with
            | None => None
            | Some None => Some None
            | Some (Some vx) =>
              match tevals n ef with
                | None => None
                | Some None => Some None
                | Some (Some (ttrue)) => Some None
                | Some (Some (tfalse)) => Some None
                | Some (Some (tvar _)) => Some None
                | Some (Some (tapp _ _)) => Some None
                | Some (Some (tabs _ ey)) =>
                  tevals n (subst_tm vx ey)
              end
          end
      end
  end.





(* ### Evaluation (Small-Step Semantics) ### *)

Inductive value : tm -> Prop :=
| V_True : 
    value ttrue
| V_False : 
    value tfalse
| V_Abs : forall T t,
    value (tabs T t)
.

Inductive step : tm -> tm -> Prop :=
| ST_AppAbs : forall x v T1 t12,
    value v ->
    step (tapp (tabs T1 t12) v) (subst_tm x t12)
| ST_App1 : forall t1 t1' t2,
    step t1 t1' ->
    step (tapp t1 t2) (tapp t1' t2)
| ST_App2 : forall f t2 t2',
    value f ->
    step t2 t2' ->
    step (tapp f t2) (tapp f t2')
.

Inductive mstep : nat -> tm -> tm -> Prop :=
| MST_Z : forall t,
    mstep 0 t t
| MST_S: forall n t1 t2 t3,
    step t1 t2 ->
    mstep n t2 t3 ->
    mstep (S n) t1 t3
.



(* automation *)

Hint Constructors venv.
Hint Unfold tenv.


Hint Unfold indexr.
Hint Unfold lengthr.

Hint Constructors ty.
Hint Constructors tm.
Hint Constructors vl.

Hint Constructors option.
Hint Constructors list.

Hint Resolve ex_intro.



(* ### Euivalence big-step env <-> big-step subst ### *)

Fixpoint subst_tm_all n venv t {struct venv} :=
  match venv with
    | vnil => t
    | vcons (vbool true) tl  => subst_tm ttrue (subst_tm_all (S n) tl t)
    | vcons (vbool false) tl => subst_tm tfalse (subst_tm_all (S n) tl t)
    | vcons (vabs venv0 T y) tl =>
      subst_tm (tabs T (shift_tm n (subst_tm_all 1 venv0 y))) (subst_tm_all (S n)tl t) 
  end.


Definition subst_tm_res t :=
  match t with
    | None => None
    | Some None => Some None
    | Some (Some (vbool true)) => Some (Some ttrue)
    | Some (Some (vbool false)) => Some (Some tfalse)
    | Some (Some (vabs venv0 T y)) =>
      Some (Some ((tabs T (subst_tm_all 1 venv0 y))))
  end.



Lemma idx_miss: forall env i l,
  i >= lengthr env ->
  indexr i env = None /\ subst_tm_all l env (tvar i) = (tvar (i-(lengthr env))).
Proof.
  intros env. induction env.
  - intros. simpl in H. simpl. 
    assert (i-0=i). omega. rewrite H0. eauto.
  - intros. simpl in H. simpl.
    destruct (IHenv i (S l)) as [A B]. omega. 
    rewrite B. simpl. 
    assert (beq_nat (i - lengthr env) 0 = false). eapply beq_nat_false_iff. omega.
    assert (beq_nat i (lengthr env) = false). eapply beq_nat_false_iff. omega.
    rewrite H0. rewrite H1. 
    assert (i - lengthr env - 1 = i - S (lengthr env)). omega.
    rewrite H2. 

    destruct v; try destruct b;  eauto.
Qed. 

Lemma idx_miss1: forall env i l,
  i >= lengthr env ->
  subst_tm_all l env (tvar i) = (tvar (i-(lengthr env))).
Proof.
  intros env. eapply idx_miss; eauto. 
Qed. 



Lemma shiftz_id: forall t,
  shift_tm 0 t = t.
Proof.
  intros. induction t; simpl; eauto; try rewrite IHt; try rewrite IHt1; try rewrite IHt2; eauto.
Qed.

Lemma subst_shift_id: forall t u l,
  subst_tm u (shift_tm (S l) t) = shift_tm l t.
Proof.
  intros t. induction t; intros; simpl; eauto.
  - assert (beq_nat (i + S l) 0 = false). eapply beq_nat_false_iff. omega. rewrite H.
    assert (i+(S l)-1=i+l). omega. rewrite H0; eauto.
  - rewrite IHt. eauto.
  - rewrite IHt1. rewrite IHt2. eauto. 
Qed.


Lemma idx_miss2: forall env i v l,
  i < lengthr env ->
  subst_tm_all l (vcons v env) (tvar i) = subst_tm_all l env (tvar i).
Proof.
  intros env. induction env.
  - intros. inversion H.
  - intros. simpl in H.
    case_eq (beq_nat i (lengthr env)); intros E.
    + 
      assert (beq_nat (i - lengthr env) 0 = true) as E1.
      eapply beq_nat_true_iff. eapply beq_nat_true_iff in E. omega.

      simpl. rewrite idx_miss1. rewrite idx_miss1. simpl. rewrite E1. 
      destruct v0; try destruct b; 
      destruct v; try destruct b; eauto.

      simpl. rewrite subst_shift_id. eauto.
      simpl. rewrite subst_shift_id. eauto.
      simpl. rewrite subst_shift_id. eauto.
      eapply beq_nat_true_iff in E. omega.
      eapply beq_nat_true_iff in E. omega.

    + assert (i < lengthr env). rewrite beq_nat_false_iff in E. omega.
      remember (vcons v env) as env1. simpl.
      subst env1. rewrite IHenv. rewrite IHenv.

      destruct v0; try destruct b.
      eapply (IHenv i (vbool true)). eauto.
      eapply (IHenv i (vbool false)). eauto.
      eapply (IHenv i (vabs v0 t t0)). eauto.
      eauto.
      eauto. 
Qed. 


Lemma idx_hit: forall env i,
  i < lengthr env ->
  subst_tm_res (Some (indexr i env)) = Some (Some (subst_tm_all 0 env (tvar i))).
Proof.
  intros env. induction env.
  - intros. inversion H.
  - intros.
    simpl in H. simpl.
    case_eq (beq_nat i (lengthr env)); intros E.
    + eapply beq_nat_true_iff in E.
      rewrite idx_miss1. subst i. simpl.
      assert (beq_nat (lengthr env - lengthr env) 0 = true). eapply beq_nat_true_iff. omega.
      rewrite H0. 
      destruct v; try destruct b; eauto.
      destruct (lengthr env). simpl.
      rewrite shiftz_id. eauto.
      rewrite shiftz_id. eauto.
      omega.
    + eapply beq_nat_false_iff in E.
      assert (i < lengthr env). omega.
      specialize (IHenv _ H0). simpl in IHenv.
      rewrite IHenv.

      destruct v; try destruct b.

      rewrite <-(idx_miss2 env i (vbool true)). simpl. eauto. eauto.
      rewrite <-(idx_miss2 env i (vbool false)). simpl. eauto. eauto.
      rewrite <-(idx_miss2 env i (vabs v t t0)). simpl. eauto. eauto.
Qed.


(* proof of equivalence *)

Theorem big_env_subst: forall n env e1 e2,
  subst_tm_all 0 env e1 = e2 ->
  subst_tm_res (teval n env e1) = (tevals n e2).
Proof.   
  intros n. induction n.
  (* z *) intros. simpl. eauto.
  (* S n *) intros.
  destruct e1; simpl; eauto.
  - (* true *)
    assert (forall env l,
              subst_tm_all l env ttrue = ttrue) as REC. {
      intros env0. induction env0; intros.
      simpl. eauto.
      simpl. destruct v; try destruct b; rewrite IHenv0; simpl; eauto. }
    rewrite REC in H. subst e2. eauto. 
  - (* false *)
    assert (forall env l,
              subst_tm_all l env tfalse = tfalse) as REC. {
      intros env0. induction env0; intros.
      simpl. eauto.
      simpl. destruct v; try destruct b; rewrite IHenv0; simpl; eauto. }
    rewrite REC in H. subst e2. eauto. 
  - (* var *)
    assert (i < lengthr env \/ i >= lengthr env) as L. omega. 
    destruct L as [L|L].
    + (* hit *) 
      simpl in H. specialize (idx_hit env i L). intros IX. rewrite H in IX.
      remember (indexr i env). destruct o.
      * simpl in IX. rewrite IX. destruct v; try destruct b; inversion IX; eauto.
      * simpl in IX. inversion IX. 
    +
      specialize (idx_miss env i 0 L). intros IX. rewrite H in IX.
      destruct IX as [A B]. rewrite A. rewrite B. eauto. 

  - (* tabs *)
    assert (forall env l,
              subst_tm_all l env (tabs t e1) = 
              (tabs t (subst_tm_all (S l) env e1))) as REC. {
    intros env0. induction env0; intros.
    simpl. eauto.
    simpl. destruct v; try destruct b; rewrite IHenv0; simpl; eauto. admit. } (* add shift *)

    rewrite REC in H. subst e2. eauto. 
  - (* tapp *)
    assert (forall env l,
              subst_tm_all l env (tapp e1_1 e1_2) = 
              (tapp (subst_tm_all l env e1_1) (subst_tm_all l env e1_2))) as REC. {
    intros env0. induction env0; intros.
    simpl. eauto.
    simpl. destruct v; try destruct b; rewrite IHenv0; simpl; eauto. }

    rewrite REC in H. subst e2.
    
    assert (subst_tm_res (teval n env e1_2) = tevals n (subst_tm_all 0 env e1_2)) as HF. eapply IHn; eauto. 
    assert (subst_tm_res (teval n env e1_1) = tevals n (subst_tm_all 0 env e1_1)) as HX. eapply IHn; eauto.
    rewrite <-HF. rewrite <-HX. simpl. 

    remember ((teval n env e1_2)) as A.
    destruct A as [[?|]|]; simpl.
    * remember ((teval n env e1_1)) as B.
      destruct B as [[?|]|]; simpl. 
      { destruct v0; try destruct b; destruct v; try destruct b; simpl; eauto.
        eapply IHn. simpl. rewrite shiftz_id. eauto. }
      destruct v; try destruct b; eauto.
      destruct v; try destruct b; eauto.  
    * eauto.
    * eauto. 
Qed.


(* ### Equivalence big-step subst <-> small-step subst ### *)

(* proof of equivalence *)

(* TODO *)



