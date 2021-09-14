module Tests exposing (..)

import AssocSet as Set
import Dict
import Elm.Parser
import Elm.Processing
import Elm.Syntax.DeclarationV2 exposing (DeclarationV2(..))
import Elm.Syntax.NodeV2 as NodeV2 exposing (NodeV2(..), TypedMeta)
import Elm.TypeInference
import Elm.TypeInference.Error exposing (Error)
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
import Fuzz exposing (Fuzzer)
import List.Extra as List
import Test exposing (Test)


type TestError
    = CouldntParse (List String)
    | CouldntInfer Error
    | CouldntFindMainModule
    | CouldntFindAnyDeclaration
    | FoundUnexpectedDeclaration (DeclarationV2 TypedMeta)


getExprType : String -> Result TestError Type
getExprType exprCode =
    let
        moduleCode =
            """
module Main exposing (main)
main = {EXPR}
"""
                |> String.replace "{EXPR}" exprCode

        mainModule =
            ( "Main", [] )
    in
    moduleCode
        |> Elm.Parser.parse
        |> Result.map (Elm.Processing.process Elm.Processing.init)
        |> Result.mapError (List.map Debug.toString >> CouldntParse)
        |> Result.andThen
            (\file ->
                Elm.TypeInference.infer (Dict.singleton mainModule file)
                    |> Result.mapError CouldntInfer
            )
        |> Result.andThen
            (\typedFiles ->
                Dict.get mainModule typedFiles
                    |> Result.fromMaybe CouldntFindMainModule
            )
        |> Result.andThen
            (\typedFile ->
                List.head typedFile.declarations
                    |> Result.fromMaybe CouldntFindAnyDeclaration
            )
        |> Result.andThen
            (\decl ->
                case decl of
                    NodeV2 _ ((FunctionDeclaration { declaration }) as val) ->
                        declaration
                            |> NodeV2.value
                            |> .expression
                            |> NodeV2.type_
                            |> Ok

                    NodeV2 _ d ->
                        Err <| FoundUnexpectedDeclaration d
            )


normalize : Type -> Type
normalize ((Forall boundVars monoType) as type_) =
    let
        allVars : List TypeVar
        allVars =
            Set.union
                (Type.freeVarsMono monoType)
                (Set.fromList boundVars)
                |> Set.toList

        newVars : List TypeVar
        newVars =
            allVars
                |> List.foldl
                    (\( style, super ) ( nextId, nextVarOrd, acc ) ->
                        case style of
                            Generated n ->
                                ( nextId + 1, nextVarOrd, ( Generated nextId, super ) :: acc )

                            Named name ->
                                ( nextId, nextVarOrd + 1, ( Named (ordToName nextVarOrd), super ) :: acc )
                    )
                    ( 0, 0, [] )
                |> (\( _, _, vars ) -> vars)

        subst : SubstitutionMap
        subst =
            List.map2 (\from to -> ( from, TypeVar to ))
                allVars
                newVars
                |> SubstitutionMap.fromList
    in
    SubstitutionMap.substitute subst type_


ordToName : Int -> String
ordToName n =
    let
        radix =
            26

        {- The functions below are stolen from fredcy/elm-parseint and tweaked
           to work similar to:

           https://en.wikipedia.org/wiki/Bijective_numeration#The_bijective_base-26_system
        -}
        charFromInt : Int -> Char
        charFromInt i =
            Char.fromCode <| i + Char.toCode 'a'

        go : Int -> String
        go i =
            if i < radix then
                String.fromChar <| charFromInt i

            else
                go (i // radix) ++ (String.fromChar <| charFromInt (modBy radix i))
    in
    go n


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
            , ( "[1.0, 2.0, 3.0]", isList (is Float) )
            , ( "[1, 2, 3.0]", isList (is Float) )
            , ( "[1.0, 2, 3]", isList (is Float) )
            , ( "[1, 2, 3]", isList isNumber )

            -- TODO Application (List (ExprWith meta))
            -- TODO OperatorApplication String InfixDirection (ExprWith meta) (ExprWith meta)
            -- TODO FunctionOrValue ModuleName String
            -- TODO IfBlock (ExprWith meta) (ExprWith meta) (ExprWith meta)
            -- TODO PrefixOperator String
            -- TODO Operator String
            -- TODO TupledExpression (List (ExprWith meta))
            -- TODO LetExpression (LetBlock meta)
            -- TODO CaseExpression (CaseBlock meta)
            -- TODO LambdaExpression (Lambda meta)
            -- TODO RecordExpr (List (LocatedNode (RecordSetter meta)))
            -- TODO ListExpr (List (ExprWith meta))
            -- TODO RecordAccess (ExprWith meta) (LocatedNode String)
            -- TODO RecordAccessFunction String
            -- TODO RecordUpdateExpression (LocatedNode String) (List (LocatedNode (RecordSetter meta)))
            -- TODO GLSLExpression String
            ]

        badExprs : List ( String, Result Error Type -> Bool )
        badExprs =
            [ ( "[1, ()]", fails )
            ]

        exprFuzzer : List ( String, a ) -> Fuzzer String
        exprFuzzer exprs =
            exprs
                |> List.map (\( expr, _ ) -> Fuzz.constant expr)
                |> Fuzz.oneOf

        allExprFuzzer : Fuzzer String
        allExprFuzzer =
            exprFuzzer (goodExprs ++ badExprs)
    in
    Test.describe "Elm.TypeInference"
        [ Test.describe "infer"
            [ Test.describe "good expressions" (List.map testExpr goodExprs)
            , Test.describe "bad expressions" (List.map testExpr badExprs)
            , Test.fuzz allExprFuzzer "e == (e)" <|
                \expr ->
                    Result.map normalize (getExprType ("(" ++ expr ++ ")"))
                        |> Expect.equal (Result.map normalize (getExprType expr))
            ]

        -- TODO number later used with an int -> coerced into an int
        -- TODO number later used with a float -> coerced into a float
        ]
