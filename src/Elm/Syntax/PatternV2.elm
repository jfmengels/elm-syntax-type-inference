module Elm.Syntax.PatternV2 exposing
    ( LocatedPattern
    , PatternV2(..)
    , PatternWith
    , TypedPattern
    , fromNodePattern
    , mapType
    , transformOnce
    )

import Elm.Syntax.Node as Node exposing (Node)
import Elm.Syntax.NodeV2 as NodeV2
    exposing
        ( LocatedMeta
        , LocatedNode
        , NodeV2(..)
        , TypedMeta
        )
import Elm.Syntax.Pattern as Pattern exposing (Pattern, QualifiedNameRef)
import Elm.TypeInference.Type exposing (TypeOrId)
import Transform


type alias LocatedPattern =
    PatternWith LocatedMeta


type alias TypedPattern =
    PatternWith TypedMeta


type alias PatternWith meta =
    NodeV2 meta (PatternV2 meta)


type PatternV2 meta
    = AllPattern
    | UnitPattern
    | CharPattern Char
    | StringPattern String
    | IntPattern Int
    | HexPattern Int
    | FloatPattern Float
    | TuplePattern (List (PatternWith meta))
    | RecordPattern (List (LocatedNode String))
    | UnConsPattern (PatternWith meta) (PatternWith meta)
    | ListPattern (List (PatternWith meta))
    | VarPattern String
    | NamedPattern QualifiedNameRef (List (PatternWith meta))
    | AsPattern (PatternWith meta) (LocatedNode String)
    | ParenthesizedPattern (PatternWith meta)


fromNodePattern : Node Pattern -> LocatedPattern
fromNodePattern node =
    let
        range =
            Node.range node

        pattern =
            Node.value node
    in
    NodeV2
        { range = range }
        (fromPattern pattern)


fromPattern : Pattern -> PatternV2 LocatedMeta
fromPattern pattern =
    let
        f =
            fromNodePattern
    in
    case pattern of
        Pattern.AllPattern ->
            AllPattern

        Pattern.UnitPattern ->
            UnitPattern

        Pattern.CharPattern a ->
            CharPattern a

        Pattern.StringPattern a ->
            StringPattern a

        Pattern.IntPattern a ->
            IntPattern a

        Pattern.HexPattern a ->
            HexPattern a

        Pattern.FloatPattern a ->
            FloatPattern a

        Pattern.TuplePattern patterns ->
            TuplePattern <| List.map f patterns

        Pattern.RecordPattern fields ->
            RecordPattern <| List.map NodeV2.fromNode fields

        Pattern.UnConsPattern p1 p2 ->
            UnConsPattern (f p1) (f p2)

        Pattern.ListPattern patterns ->
            ListPattern <| List.map f patterns

        Pattern.VarPattern a ->
            VarPattern a

        Pattern.NamedPattern a patterns ->
            NamedPattern a <| List.map f patterns

        Pattern.AsPattern p1 a ->
            AsPattern (f p1) (NodeV2.fromNode a)

        Pattern.ParenthesizedPattern p1 ->
            ParenthesizedPattern (f p1)


mapType : (TypeOrId -> TypeOrId) -> TypedPattern -> TypedPattern
mapType fn node =
    NodeV2.mapMeta (\meta -> { meta | type_ = fn meta.type_ }) node


transformOnce : (PatternWith meta -> PatternWith meta) -> PatternWith meta -> PatternWith meta
transformOnce pass expr =
    Transform.transformOnce
        recurse
        pass
        expr


recurse : (PatternWith meta -> PatternWith meta) -> PatternWith meta -> PatternWith meta
recurse fn node =
    node
        |> NodeV2.map
            (\expr ->
                case expr of
                    AllPattern ->
                        expr

                    UnitPattern ->
                        expr

                    CharPattern _ ->
                        expr

                    StringPattern _ ->
                        expr

                    IntPattern _ ->
                        expr

                    HexPattern _ ->
                        expr

                    FloatPattern _ ->
                        expr

                    TuplePattern patterns ->
                        TuplePattern (List.map fn patterns)

                    RecordPattern _ ->
                        expr

                    UnConsPattern p1 p2 ->
                        UnConsPattern (fn p1) (fn p2)

                    ListPattern patterns ->
                        ListPattern (List.map fn patterns)

                    VarPattern _ ->
                        expr

                    NamedPattern ref patterns ->
                        NamedPattern ref (List.map fn patterns)

                    AsPattern p1 name ->
                        AsPattern (fn p1) name

                    ParenthesizedPattern p1 ->
                        ParenthesizedPattern (fn p1)
            )
