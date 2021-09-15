module Tests exposing (..)

import AssocList
import AssocSet as Set
import Dict
import Elm.Parser
import Elm.Processing
import Elm.Syntax.DeclarationV2 exposing (DeclarationV2(..))
import Elm.Syntax.ExpressionV2 as ExpressionV2
import Elm.Syntax.NodeV2 as NodeV2 exposing (NodeV2(..), TypedMeta)
import Elm.TypeInference
import Elm.TypeInference.Error exposing (Error)
import Elm.TypeInference.Helpers exposing (TestError(..), getExprType)
import Elm.TypeInference.SubstitutionMap as SubstitutionMap exposing (SubstitutionMap)
import Elm.TypeInference.Type as Type
    exposing
        ( MonoType(..)
        , SuperType(..)
        , Type(..)
        , TypeVar
        , TypeVarStyle(..)
        )
import Expect
import Test exposing (Test)


testExpr : ( String, Result Error Type -> Bool ) -> Test
testExpr ( exprCode, predicate ) =
    Test.test exprCode <|
        \() ->
            case getExprType exprCode of
                Err (CouldntInfer err) ->
                    predicate (Err err)
                        |> Expect.true ("Has failed in a bad way: " ++ Debug.toString err)

                Ok type_ ->
                    predicate (Ok type_)
                        |> Expect.true ("Has inferred a bad type: " ++ Type.toString type_)

                Err err ->
                    Expect.fail <| "Has failed (but shouldn't): " ++ Debug.toString err


is : MonoType -> Result Error Type -> Bool
is expected actual =
    Ok (Forall [] expected) == actual


fails : Result Error Type -> Bool
fails actual =
    case actual of
        Err _ ->
            True

        Ok _ ->
            False


isNumber : Result Error Type -> Bool
isNumber actual =
    case actual of
        Ok (Forall [] (TypeVar ( _, Number ))) ->
            True

        _ ->
            False


isList : (Result Error Type -> Bool) -> Result Error Type -> Bool
isList innerCheck actual =
    case actual of
        Ok (Forall [] (List inner)) ->
            innerCheck (Ok (Forall [] inner))

        _ ->
            False


isTuple : (Result Error Type -> Bool) -> (Result Error Type -> Bool) -> Result Error Type -> Bool
isTuple check1 check2 actual =
    case actual of
        Ok (Forall [] (Tuple t1 t2)) ->
            check1 (Ok (Forall [] t1))
                && check2 (Ok (Forall [] t2))

        _ ->
            False


isFunction : (Result Error Type -> Bool) -> (Result Error Type -> Bool) -> Result Error Type -> Bool
isFunction fromCheck toCheck actual =
    case actual of
        Ok (Forall [] (Function { from, to })) ->
            fromCheck (Ok (Forall [] from)) && toCheck (Ok (Forall [] to))

        _ ->
            False


isVar : Result Error Type -> Bool
isVar actual =
    case actual of
        Ok (Forall [] (TypeVar _)) ->
            True

        _ ->
            False


isRecord : List ( String, Result Error Type -> Bool ) -> Result Error Type -> Bool
isRecord fieldChecks actual =
    case actual of
        Ok (Forall [] (Record fields)) ->
            List.all
                (\( field, check ) ->
                    case Dict.get field fields of
                        Nothing ->
                            False

                        Just fieldType ->
                            check (Ok (Forall [] fieldType))
                )
                fieldChecks

        _ ->
            False


isExtensibleRecord : (Result Error Type -> Bool) -> List ( String, Result Error Type -> Bool ) -> Result Error Type -> Bool
isExtensibleRecord baseRecordCheck fieldChecks actual =
    case actual of
        Ok (Forall [] (ExtensibleRecord r)) ->
            baseRecordCheck (Ok (Forall [] r.type_))
                && List.all
                    (\( field, check ) ->
                        case Dict.get field r.fields of
                            Nothing ->
                                False

                            Just fieldType ->
                                check (Ok (Forall [] fieldType))
                    )
                    fieldChecks

        _ ->
            False


suite : Test
suite =
    let
        goodExprs : List ( String, Result Error Type -> Bool )
        goodExprs =
            [ ( "()", is Unit )
            , ( "123", isNumber )
            , ( "0x123", isNumber )
            , ( "42.0", is Float )
            , ( "-123", isNumber )
            , ( "-0x123", isNumber )
            , ( "-123.0", is Float )
            , ( "\"ABC\"", is String )
            , ( "'A'", is Char )
            , ( "(42.0)", is Float )
            , ( "('a', ())", is (Tuple Char Unit) )
            , ( "('a', (), 123.4)", is (Tuple3 Char Unit Float) )
            , ( "[1.0, 2.0, 3.0]", isList (is Float) )
            , ( "[1, 2, 3.0]", isList (is Float) )
            , ( "[1.0, 2, 3]", isList (is Float) )
            , ( "[1, 2, 3]", isList isNumber )
            , ( "[(1,'a'),(2,'b')]", isList (isTuple isNumber (is Char)) )
            , ( "\\x -> 1", isFunction isVar isNumber )
            , ( "\\x y -> 1", isFunction isVar (isFunction isVar isNumber) )
            , ( "\\() -> 1", isFunction (is Unit) isNumber )
            , ( "\\x () -> 1", isFunction isVar (isFunction (is Unit) isNumber) )
            , ( "\\() x -> 1", isFunction (is Unit) (isFunction isVar isNumber) )
            , ( "{}", isRecord [] )
            , ( "{a = 1}", isRecord [ ( "a", isNumber ) ] )
            , ( "{a = 1, b = ()}", isRecord [ ( "a", isNumber ), ( "b", is Unit ) ] )
            , ( ".a", isFunction (isExtensibleRecord isVar [ ( "a", isVar ) ]) isVar )

            -- TODO Application (List (ExprWith meta))
            -- TODO OperatorApplication String InfixDirection (ExprWith meta) (ExprWith meta)
            -- TODO FunctionOrValue ModuleName String
            -- TODO IfBlock (ExprWith meta) (ExprWith meta) (ExprWith meta)
            -- TODO PrefixOperator String
            -- TODO Operator String
            -- TODO LetExpression (LetBlock meta)
            -- TODO CaseExpression (CaseBlock meta)
            -- TODO RecordAccess (ExprWith meta) (LocatedNode String)
            -- TODO RecordUpdateExpression (LocatedNode String) (List (LocatedNode (RecordSetter meta)))
            -- TODO GLSLExpression String
            ]

        badExprs : List ( String, Result Error Type -> Bool )
        badExprs =
            [ ( "[1, ()]", fails )
            , ( "fn 1", fails )
            ]
    in
    Test.describe "Elm.TypeInference"
        [ Test.describe "infer"
            [ Test.describe "good expressions" (List.map testExpr goodExprs)
            , Test.describe "bad expressions" (List.map testExpr badExprs)
            , Test.describe "e == (e)" <|
                List.map
                    (\( expr, _ ) ->
                        Test.test expr <|
                            \() ->
                                Result.map Type.normalize (getExprType ("(" ++ expr ++ ")"))
                                    |> Expect.equal (Result.map Type.normalize (getExprType expr))
                    )
                    goodExprs
            ]

        -- TODO number later used with an int -> coerced into an int
        -- TODO number later used with a float -> coerced into a float
        ]
