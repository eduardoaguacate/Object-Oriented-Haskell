module MemoryAllocator where 
import Data.Decimal
import DataTypes
import Quadruple
import SymbolTable
import ClassSymbolTable
import Text.Show.Pretty
import qualified Data.HashMap.Strict as Map
import ExpressionOptimizer
import CodeGen
import Data.List (sortBy)
import Data.Ord (comparing)
import Data.Function (on)


startIntGlobalMemory = 1
endIntGlobalMemory = 4000

startDecimalGlobalMemory = 4001
endDecimalGlobalMemory = 8000

startStringGlobalMemory = 8001
endStringGlobalMemory = 12000

startBoolGlobalMemory = 12001
endBoolGlobalMemory = 16000

startIntLocalMemory = 16001
endIntLocalMemory = 20000

startDecimalLocalMemory = 20001
endDecimaLocalMemory = 24000

startStringLocalMemory = 24001
endStringLocalMemory = 26000

startBoolLocalMemory = 26001
endBoolLocalMemory = 30000

startIntLiteralMemory = 64001
endIntLiteralMemory = 68000

startDecimalLiteralMemory = 68001
endDecimalLiteralMemory = 72000

startStringLiteralMemory = 76001
endStringLiteralMemory = 80000

startBoolLiteralMemory = 80001
endBoolLiteralMemory = 84000


startObjectGlobalMemory = 100001
endObjectGlobalMemory = 104000

startObjectLocalMemory = 104001
endObjectLocalMemory = 108000


startMemoryAllocation :: Program -> SymbolTable -> ClassSymbolTable -> IO()
startMemoryAllocation (Program classes functions variables (Block statements)) symTab classSymTab =
            let (newLiteralCounters,constantAddressMap) =  (prepareConstantAddressMap statements (startIntLiteralMemory,startDecimalLiteralMemory,startStringLiteralMemory,startBoolLiteralMemory)
                                                                (Map.empty))
            in let (newLiteralCounters2,constantAddressMap2) = fillFromExpression newLiteralCounters constantAddressMap (ExpressionLitVar (DecimalLiteral 0.0))
            in let (newLiteralCounters3,constantAddressMap3) = fillFromExpression newLiteralCounters2 constantAddressMap2 (ExpressionLitVar (IntegerLiteral 0))
            in let (newLiteralCounters4,constantAddressMap4) = fillFromExpression newLiteralCounters3 constantAddressMap3 (ExpressionLitVar (StringLiteral ""))
            in let (newLiteralCounters5,constantAddressMap5) = fillFromExpression newLiteralCounters4 constantAddressMap4 (ExpressionLitVar (BoolLiteral True))
            in let (varCounters,newIdMap,objectAddressMap) = (prepareAddressMapsFromSymbolTable symTab classSymTab (startIntGlobalMemory,startDecimalGlobalMemory,startStringGlobalMemory,startBoolGlobalMemory, startObjectGlobalMemory)
                                                                (Map.empty) (Map.empty))
            in do putStrLn $ ppShow $ (sortBy (compare `on` snd) (Map.toList newIdMap) )
                  putStrLn $ ppShow $ (sortBy (compare `on` snd) ( Map.toList constantAddressMap5 ) )
                  putStrLn $ ppShow $ (sortBy (compare `on` fst) (Map.toList objectAddressMap) )
                  startCodeGen (Program classes functions variables (Block statements)) symTab classSymTab varCounters newIdMap constantAddressMap5

prepareConstantAddressMap :: [Statement] -> LiteralCounters -> ConstantAddressMap -> (LiteralCounters, ConstantAddressMap)
prepareConstantAddressMap [] literalCounters constantAddressMap = (literalCounters,constantAddressMap)
prepareConstantAddressMap (st : sts) literalCounters constantAddressMap = 
            let (newLiteralCounters, newConsAddressMap) = fillFromStatement st literalCounters constantAddressMap
            in let (newLiteralCounters2, newConsAddressMap2) = (prepareConstantAddressMap sts newLiteralCounters newConsAddressMap)
                in (newLiteralCounters2, newConsAddressMap2)


fillFromLiteralOrVariables :: [LiteralOrVariable] -> LiteralCounters -> ConstantAddressMap -> (LiteralCounters, ConstantAddressMap)
fillFromLiteralOrVariables [] literalCounters constantAddressMap = (literalCounters,constantAddressMap)
fillFromLiteralOrVariables (litVar : litVars) literalCounters constantAddressMap
            = let (newLiteralCounters,newConsAddressMap) = fillFromExpression literalCounters constantAddressMap (ExpressionLitVar litVar)
                in fillFromLiteralOrVariables litVars newLiteralCounters newConsAddressMap

fillFromListOfLiteralOrVariables :: [[LiteralOrVariable]] -> LiteralCounters -> ConstantAddressMap -> (LiteralCounters, ConstantAddressMap)
fillFromListOfLiteralOrVariables [] literalCounters constantAddressMap = (literalCounters,constantAddressMap)
fillFromListOfLiteralOrVariables (listLitVars : rest) literalCounters constantAddressMap
            = let (newLiteralCounters, newConsAddressMap) = fillFromLiteralOrVariables listLitVars literalCounters constantAddressMap
                in fillFromListOfLiteralOrVariables rest newLiteralCounters newConsAddressMap

fillFromVariable :: Variable -> LiteralCounters -> ConstantAddressMap -> (LiteralCounters, ConstantAddressMap)
fillFromVariable (VariableAssignmentLiteralOrVariable dataType identifier literalOrVariable) literalCounters constantAddressMap =
                                fillFromExpression literalCounters constantAddressMap (ExpressionLitVar literalOrVariable) 
fillFromVariable (VariableAssignment1D _ _ literalOrVariables) literalCounters constantAddressMap = 
                                fillFromLiteralOrVariables literalOrVariables literalCounters constantAddressMap
fillFromVariable (VariableAssignment2D dt identifier listOfListVars) literalCounters constantAddressMap = 
                                fillFromListOfLiteralOrVariables listOfListVars literalCounters constantAddressMap
fillFromVariable (VariableAssignmentObject _ _ (ObjectCreation _ params)) literalCounters constantAddressMap = 
                                fillFromCallParams literalCounters constantAddressMap params
fillFromVariable _ literalCounters constantAddressMap  = (literalCounters,constantAddressMap)


fillFromAssignment :: Assignment -> LiteralCounters -> ConstantAddressMap -> (LiteralCounters, ConstantAddressMap)
fillFromAssignment (AssignmentExpression identifier expression) literalCounters constantAddressMap = fillFromExpression literalCounters constantAddressMap expression
fillFromAssignment  (AssignmentObjectMemberExpression (ObjectMember objectIdentifier attrIdentifier) expression) literalCounters constantAddressMap =  fillFromExpression literalCounters constantAddressMap expression

fillFromAssignment  (AssignmentArrayExpression _ ((ArrayAccessExpression innerExp) : []) expression) literalCounters constantAddressMap =  
                                                                                        let (newLiteralCounters,newConsAddressMap) = fillFromExpression literalCounters constantAddressMap innerExp
                                                                                        in fillFromExpression newLiteralCounters newConsAddressMap expression
fillFromAssignment  (AssignmentArrayExpression _ ((ArrayAccessExpression innerExpRow) : (ArrayAccessExpression innerExpCol)  : []) expression) literalCounters constantAddressMap = 
                                                                                                                let (newLiteralCounters,newConsAddressMap) = fillFromExpression literalCounters constantAddressMap innerExpRow
                                                                                                                    in let (newLiteralCounters2,newConsAddressMap2) = fillFromExpression newLiteralCounters newConsAddressMap innerExpCol
                                                                                                                        in fillFromExpression newLiteralCounters2 newConsAddressMap2 expression

fillFromAssignment _ literalCounters constantAddressMap  = (literalCounters,constantAddressMap)

fillFromStatement :: Statement -> LiteralCounters -> ConstantAddressMap -> (LiteralCounters, ConstantAddressMap)
fillFromStatement (AssignStatement assignment) literalCounters constantAddressMap = fillFromAssignment assignment literalCounters constantAddressMap
fillFromStatement (VariableStatement var) literalCounters constantAddressMap = fillFromVariable var literalCounters constantAddressMap

fillFromStatement (ConditionStatement (If expression (Block statements))) literalCounters constantAddressMap = 
                                                let (newLiteralCounters, newConsAddressMap) = fillFromExpression literalCounters constantAddressMap expression
                                                    in let (newLiteralCounters2, newConsAddressMap2) = prepareConstantAddressMap statements newLiteralCounters newConsAddressMap
                                                        in (newLiteralCounters2, newConsAddressMap2)  
fillFromStatement (ConditionStatement (IfElse expression (Block statements) (Block statements2)))literalCounters constantAddressMap = 
                                                let (newLiteralCounters, newConsAddressMap) = fillFromExpression literalCounters constantAddressMap expression
                                                    in let (newLiteralCounters2, newConsAddressMap2) = prepareConstantAddressMap statements newLiteralCounters newConsAddressMap
                                                        in prepareConstantAddressMap statements2 newLiteralCounters2 newConsAddressMap2  
fillFromStatement (CycleStatement (CycleWhile (While expression (Block statements)))) literalCounters constantAddressMap = 
                let (newLiteralCounters, newConsAddressMap) = fillFromExpression literalCounters constantAddressMap expression
                    in let (newLiteralCounters2, newConsAddressMap2) = prepareConstantAddressMap statements newLiteralCounters newConsAddressMap
                        in (newLiteralCounters2, newConsAddressMap2)
fillFromStatement (CycleStatement (CycleFor (For lowerRange greaterRange (Block statements)))) (intLitC,decLitC, strLitC, boolLitC) constantAddressMap =
                                                             case (Map.lookup ("<int>" ++ (show lowerRange)) constantAddressMap) of
                                                                Just _ -> 
                                                                        case (Map.lookup ("<int>" ++ (show greaterRange)) constantAddressMap) of
                                                                            Just _ -> ( prepareConstantAddressMap statements (intLitC, decLitC, strLitC, boolLitC) constantAddressMap)
                                                                            _ -> let newConsAddressMap2 = (Map.insert ("<int>" ++ (show greaterRange)) intLitC constantAddressMap)
                                                                                    in ( prepareConstantAddressMap statements (intLitC + 1, decLitC, strLitC, boolLitC) newConsAddressMap2 )
                                                                _ -> let newConsAddressMap = (Map.insert ("<int>" ++ (show lowerRange)) intLitC constantAddressMap)
                                                                        in case (Map.lookup ("<int>" ++ (show greaterRange)) constantAddressMap) of
                                                                            Just _ -> ( prepareConstantAddressMap statements (intLitC + 1, decLitC, strLitC, boolLitC) newConsAddressMap ) 
                                                                            _ -> let newConsAddressMap2 = (Map.insert ("<int>" ++ (show greaterRange)) (intLitC + 1) newConsAddressMap)
                                                                                    in ( prepareConstantAddressMap statements (intLitC + 2, decLitC, strLitC, boolLitC) newConsAddressMap2 )
fillFromStatement (CycleStatement (CycleForVar statements)) literalCounters constantAddressMap = prepareConstantAddressMap statements literalCounters constantAddressMap
fillFromStatement (DPMStatement assignment) literalCounters constantAddressMap = fillFromStatement (AssignStatement assignment) literalCounters constantAddressMap
fillFromStatement (FunctionCallStatement functionCall) literalCounters constantAddressMap = fillFromFunctionCall functionCall literalCounters constantAddressMap
fillFromStatement (ReturnStatement (ReturnExp expression)) literalCounters constantAddressMap = fillFromExpression literalCounters constantAddressMap expression
fillFromStatement (ReturnStatement (ReturnFunctionCall functionCall)) literalCounters constantAddressMap = fillFromFunctionCall functionCall literalCounters constantAddressMap
fillFromStatement (DisplayStatement displays) literalCounters constantAddressMap = fillFromDisplays displays literalCounters constantAddressMap
                                                                where 
                                                                    fillFromDisplays :: [Display] -> LiteralCounters -> ConstantAddressMap -> (LiteralCounters,ConstantAddressMap)
                                                                    fillFromDisplays [] literalCounters constantAddressMap = (literalCounters,constantAddressMap)
                                                                    fillFromDisplays (disp : disps) literalCounters constantAddressMap = 
                                                                            let (newLiteralCounters2,newConsAddressMap) = fillFromDisplay disp literalCounters constantAddressMap
                                                                            in fillFromDisplays disps newLiteralCounters2 newConsAddressMap

                                                                    fillFromDisplay :: Display -> LiteralCounters -> ConstantAddressMap -> (LiteralCounters,ConstantAddressMap)
                                                                    fillFromDisplay (DisplayLiteralOrVariable litOrVar) literalCounters constantAddressMap =
                                                                        fillFromExpression literalCounters constantAddressMap (ExpressionLitVar litOrVar) 
                                                                    fillFromDisplay (DisplayFunctionCall funcCall) literalCounters constantAddressMap =
                                                                        fillFromExpression literalCounters constantAddressMap (ExpressionFuncCall funcCall)
                                                                    fillFromDisplay (DisplayVarArrayAccess identifier arrayAccess) literalCounters constantAddressMap =
                                                                        fillFromExpression literalCounters constantAddressMap (ExpressionVarArray identifier arrayAccess)  
                                                                    fillFromDisplay _ literalCounters constantAddressMap =
                                                                        (literalCounters,constantAddressMap)  
fillFromStatement _ literalCounters constantAddressMap = (literalCounters,constantAddressMap)


fillFromFunctionCall :: FunctionCall -> LiteralCounters  -> ConstantAddressMap -> (LiteralCounters,ConstantAddressMap)
fillFromFunctionCall (FunctionCallVar _ callParams) literalCounters constantAddressMap = 
                            fillFromCallParams literalCounters constantAddressMap callParams
fillFromFunctionCall (FunctionCallObjMem (ObjectMember _ _) callParams) literalCounters constantAddressMap = 
                            fillFromCallParams literalCounters constantAddressMap callParams


fillFromCallParams :: LiteralCounters -> ConstantAddressMap -> [Params] -> (LiteralCounters,ConstantAddressMap)
fillFromCallParams literalCounters constantAddressMap [] = (literalCounters,constantAddressMap)
fillFromCallParams literalCounters constantAddressMap ((ParamsExpression exp) : params) =
        let (newLiteralCounters,newConsAddressMap) = fillFromExpression literalCounters constantAddressMap exp
            in fillFromCallParams newLiteralCounters newConsAddressMap params
                
prepareAddressMapsFromSymbolTable :: SymbolTable -> ClassSymbolTable -> VariableCounters -> IdentifierAddressMap -> ObjectAddressMap -> (VariableCounters,IdentifierAddressMap,ObjectAddressMap)
prepareAddressMapsFromSymbolTable symTab classSymTab counters identifierAddressMap objAddressMap = 
                            let symTabList = (Map.toList symTab)
                            in fillIdentifierAddressMap symTabList classSymTab identifierAddressMap objAddressMap counters  

fillIdentifierAddressMap :: [(Identifier,Symbol)] -> ClassSymbolTable -> IdentifierAddressMap -> ObjectAddressMap -> VariableCounters -> (VariableCounters,IdentifierAddressMap,ObjectAddressMap) 
fillIdentifierAddressMap [] classSymTab identifierAddressMap objAddressMap varCounters = (varCounters,identifierAddressMap,objAddressMap)
fillIdentifierAddressMap ( (identifier,(SymbolVar (TypePrimitive prim []) _ _)) : rest ) classSymTab identifierAddressMap objAddressMap
                                                                    (intGC,decGC,strGC,boolGC,objGC)  |
                                                                    intGC <= endIntGlobalMemory
                                                                    && decGC <= endDecimalGlobalMemory
                                                                    && strGC <= endStringGlobalMemory 
                                                                    && boolGC <= endBoolGlobalMemory =
                            case prim of
                                PrimitiveBool -> let newIdMap = (Map.insert identifier boolGC identifierAddressMap)
                                                    in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap  
                                                            (intGC,decGC,strGC,boolGC + 1,objGC))
                                PrimitiveInt -> let newIdMap = (Map.insert identifier intGC identifierAddressMap)
                                                    in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC + 1,decGC,strGC,boolGC,objGC))

                                PrimitiveInteger -> let newIdMap = (Map.insert identifier intGC identifierAddressMap)
                                                        in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC + 1,decGC,strGC,boolGC,objGC)) 
                                PrimitiveString -> let newIdMap = (Map.insert identifier strGC identifierAddressMap)
                                                        in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC,decGC,strGC + 1,boolGC,objGC)) 
                                PrimitiveMoney -> let newIdMap = (Map.insert identifier decGC identifierAddressMap)
                                                        in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC,decGC + 1,strGC,boolGC,objGC))
                                PrimitiveDouble -> let newIdMap = (Map.insert identifier decGC identifierAddressMap)
                                                        in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC,decGC + 1,strGC,boolGC,objGC))
fillIdentifierAddressMap ( (identifier,(SymbolVar (TypeClassId classId arrayAccess) _ _)) : rest ) classSymTab identifierAddressMap objAddressMap
                                                                    (intGC,decGC,strGC,boolGC,objGC)  |
                                                                    intGC <= endIntGlobalMemory
                                                                    && decGC <= endDecimalGlobalMemory
                                                                    && strGC <= endStringGlobalMemory 
                                                                    && boolGC <= endBoolGlobalMemory
                                                                    && objGC <= endObjectGlobalMemory =
                                let ((intGC1,decGC1,strGC1,boolGC1,objGC1), idMapFromObject, newObjAddressMap) = insertObjectInObjectAddressMap (TypeClassId classId arrayAccess) classSymTab objAddressMap (intGC,decGC,strGC,boolGC,objGC)    
                                in case (arrayAccess) of 
                                    [] -> let newIdMap = (Map.insert identifier objGC1 identifierAddressMap) 
                                              newObjMap = (Map.insert objGC1 idMapFromObject newObjAddressMap)
                                              in (fillIdentifierAddressMap rest classSymTab newIdMap newObjMap 
                                                            (intGC1,decGC1,strGC1,boolGC1,objGC1 + 1))
                                    (("[",size,"]") : []) -> 
                                         let newIdMap = (Map.insert identifier objGC1 identifierAddressMap) 
                                             newObjMap = (Map.insert objGC1 idMapFromObject newObjAddressMap)
                                             in (fillIdentifierAddressMap rest classSymTab newIdMap newObjMap 
                                                                (intGC1,decGC1,strGC1,boolGC1,objGC1 + size))
                                    (("[",rows,"]") : ("[",cols,"]")  : [] ) -> 
                                          let newIdMap = (Map.insert identifier objGC1 identifierAddressMap) 
                                              newObjMap = (Map.insert objGC1 idMapFromObject newObjAddressMap)
                                              in (fillIdentifierAddressMap rest classSymTab newIdMap newObjMap 
                                                            (intGC1,decGC1,strGC1,boolGC1,objGC1 + rows * cols))
fillIdentifierAddressMap ( (identifier,(SymbolVar (TypePrimitive prim (("[",size,"]") : [])) _ _)) : rest ) classSymTab identifierAddressMap objAddressMap
                                                                    (intGC,decGC,strGC,boolGC,objGC)  |
                                                                    intGC <= endIntGlobalMemory
                                                                    && decGC <= endDecimalGlobalMemory
                                                                    && strGC <= endStringGlobalMemory 
                                                                    && boolGC <= endBoolGlobalMemory =
                            case prim of
                                PrimitiveBool -> let newIdMap = (Map.insert identifier boolGC identifierAddressMap)
                                                    in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC,decGC,strGC,boolGC + size,objGC))
                                PrimitiveInt -> let newIdMap = (Map.insert identifier intGC identifierAddressMap)
                                                    in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC + size,decGC,strGC,boolGC,objGC))

                                PrimitiveInteger -> let newIdMap = (Map.insert identifier intGC identifierAddressMap)
                                                        in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC + size,decGC,strGC,boolGC,objGC)) 
                                PrimitiveString -> let newIdMap = (Map.insert identifier strGC identifierAddressMap)
                                                        in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC,decGC,strGC + size,boolGC,objGC)) 
                                PrimitiveMoney -> let newIdMap = (Map.insert identifier decGC identifierAddressMap)
                                                        in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC,decGC + size,strGC,boolGC,objGC))
                                PrimitiveDouble -> let newIdMap = (Map.insert identifier decGC identifierAddressMap)
                                                        in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC,decGC + size,strGC,boolGC,objGC))

fillIdentifierAddressMap ( (identifier,(SymbolVar (TypePrimitive prim (("[",rows,"]") : ("[",cols,"]")  : [])) _ _)) : rest ) classSymTab identifierAddressMap objAddressMap
                                                                    (intGC,decGC,strGC,boolGC,objGC)  |
                                                                    intGC <= endIntGlobalMemory
                                                                    && decGC <= endDecimalGlobalMemory
                                                                    && strGC <= endStringGlobalMemory 
                                                                    && boolGC <= endBoolGlobalMemory =
                            case prim of
                                PrimitiveBool -> let newIdMap = (Map.insert identifier boolGC identifierAddressMap)
                                                    in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC,decGC,strGC,boolGC + rows * cols,objGC))
                                PrimitiveInt -> let newIdMap = (Map.insert identifier intGC identifierAddressMap)
                                                    in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC + rows * cols,decGC,strGC,boolGC,objGC))

                                PrimitiveInteger -> let newIdMap = (Map.insert identifier intGC identifierAddressMap)
                                                        in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC + rows * cols,decGC,strGC,boolGC,objGC)) 
                                PrimitiveString -> let newIdMap = (Map.insert identifier strGC identifierAddressMap)
                                                        in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC,decGC,strGC + rows * cols,boolGC,objGC)) 
                                PrimitiveMoney -> let newIdMap = (Map.insert identifier decGC identifierAddressMap)
                                                        in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC,decGC + rows * cols,strGC,boolGC,objGC))
                                PrimitiveDouble -> let newIdMap = (Map.insert identifier decGC identifierAddressMap)
                                                        in (fillIdentifierAddressMap rest classSymTab newIdMap objAddressMap 
                                                            (intGC,decGC + rows * cols,strGC,boolGC,objGC))

                                -- PrimitiveBool -> (Map.union (Map.insert identifier boolGC identifierAddressMap)
                                --                             (fillIdentifierAddressMap rest identifierAddressMap
                                --                             (intGC,decGC,strGC,boolGC + rows * cols)))
                                -- PrimitiveInt -> (Map.union (Map.insert identifier intGC identifierAddressMap)
                                --                             (fillIdentifierAddressMap rest identifierAddressMap
                                --                             (intGC + rows * cols,decGC,strGC,boolGC)))
                                -- PrimitiveInteger -> (Map.union (Map.insert identifier intGC identifierAddressMap)
                                --                             (fillIdentifierAddressMap rest identifierAddressMap
                                --                             (intGC + rows * cols,decGC,strGC,boolGC)))
                                -- PrimitiveString -> (Map.union (Map.insert identifier strGC identifierAddressMap)
                                --                             (fillIdentifierAddressMap rest identifierAddressMap
                                --                             (intGC,decGC,strGC + rows * cols,boolGC)))
                                -- PrimitiveMoney -> (Map.union (Map.insert identifier decGC identifierAddressMap)
                                --                             (fillIdentifierAddressMap rest identifierAddressMap
                                --                             (intGC,decGC + rows * cols,strGC,boolGC)))
                                -- PrimitiveDouble -> (Map.union (Map.insert identifier decGC identifierAddressMap)
                                --                             (fillIdentifierAddressMap rest identifierAddressMap
                                --                             (intGC,decGC + rows * cols,strGC,boolGC)))
-- MARK TODO: Objetos, funciones
fillIdentifierAddressMap (x : xs) classSymTab identifierAddressMap objAddressMap (intGC,decGC,strGC,boolGC,objGC) = 
            (fillIdentifierAddressMap xs classSymTab identifierAddressMap objAddressMap
                                                            (intGC,decGC,strGC,boolGC,objGC))

insertObjectInObjectAddressMap ::  Type -> ClassSymbolTable -> ObjectAddressMap -> VariableCounters -> (VariableCounters,IdentifierAddressMap,ObjectAddressMap) 
insertObjectInObjectAddressMap (TypeClassId classId arrayAccess) classSymTab objAddressMap (intGC,decGC,strGC,boolGC,objGC) =
                                case (Map.lookup classId classSymTab) of
                                    Just symbolTableOfClass -> 
                                        prepareAddressMapsFromSymbolTable symbolTableOfClass classSymTab (intGC,decGC,strGC,boolGC,objGC) (Map.empty) objAddressMap 


                            
fillFromExpression :: LiteralCounters -> ConstantAddressMap -> Expression -> (LiteralCounters,ConstantAddressMap)
fillFromExpression literalCounters constantAddressMap expression = fillFromExpressionAdaptee literalCounters constantAddressMap (reduceExpression expression)


fillFromExpressionAdaptee :: LiteralCounters -> ConstantAddressMap -> Expression -> (LiteralCounters,ConstantAddressMap)
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionMult exp1 exp2) = fillFromTwoExpressions literalCounters constantAddressMap exp1 exp2
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionPlus exp1 exp2) = fillFromTwoExpressions literalCounters constantAddressMap exp1 exp2
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionPow exp1 exp2) = fillFromTwoExpressions literalCounters constantAddressMap exp1 exp2
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionDiv exp1 exp2) = fillFromTwoExpressions literalCounters constantAddressMap exp1 exp2
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionMinus exp1 exp2) = fillFromTwoExpressions literalCounters constantAddressMap exp1 exp2
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionPars exp) = fillFromExpression literalCounters constantAddressMap exp
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionNeg exp) = fillFromExpression literalCounters constantAddressMap exp
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionMod exp1 exp2) = fillFromTwoExpressions literalCounters constantAddressMap exp1 exp2
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionGreater exp1 exp2) = fillFromTwoExpressions literalCounters constantAddressMap exp1 exp2
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionLower exp1 exp2) = fillFromTwoExpressions literalCounters constantAddressMap exp1 exp2
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionGreaterEq exp1 exp2) = fillFromTwoExpressions literalCounters constantAddressMap exp1 exp2
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionLowerEq exp1 exp2) = fillFromTwoExpressions literalCounters constantAddressMap exp1 exp2
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionEqEq exp1 exp2) = fillFromTwoExpressions literalCounters constantAddressMap exp1 exp2
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionNotEq exp1 exp2) = fillFromTwoExpressions literalCounters constantAddressMap exp1 exp2
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionAnd exp1 exp2) = fillFromTwoExpressions literalCounters constantAddressMap exp1 exp2
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionOr exp1 exp2) = fillFromTwoExpressions literalCounters constantAddressMap exp1 exp2
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionNot exp) = fillFromExpression literalCounters constantAddressMap exp
fillFromExpressionAdaptee (intLitC,decLitC, strLitC, boolLitC) constantAddressMap (ExpressionLitVar litOrVar)
                    | intLitC <= endIntLiteralMemory
                     && decLitC <= endDecimalLiteralMemory
                     && strLitC <= endStringLiteralMemory
                     && boolLitC <= endBoolLiteralMemory = 
                    case litOrVar of
                         IntegerLiteral int -> case (Map.lookup ("<int>" ++ (show int)) constantAddressMap) of
                                                    Just _ -> ((intLitC, decLitC, strLitC, boolLitC), constantAddressMap)
                                                    _ ->  let newConsAddressMap = (Map.insert ("<int>" ++ (show int)) intLitC constantAddressMap)
                                                                in ((intLitC + 1, decLitC, strLitC, boolLitC), newConsAddressMap)
                         DecimalLiteral dec -> case (Map.lookup ("<dec>" ++ (show dec)) constantAddressMap) of
                                                    Just _ -> ((intLitC, decLitC, strLitC, boolLitC), constantAddressMap)
                                                    _ -> let newConsAddressMap = (Map.insert ("<dec>" ++ (show dec)) decLitC constantAddressMap)
                                                            in ((intLitC, decLitC + 1, strLitC, boolLitC), newConsAddressMap)
                         StringLiteral str -> case (Map.lookup ("<str>" ++ (show str)) constantAddressMap) of
                                                    Just _ -> ((intLitC, decLitC, strLitC, boolLitC), constantAddressMap)
                                                    _ -> let newConsAddressMap = (Map.insert ("<str>" ++ str) strLitC constantAddressMap)
                                                            in ((intLitC, decLitC, strLitC + 1, boolLitC), newConsAddressMap)
                         BoolLiteral bool -> case (Map.lookup ("<bool>" ++ (show bool)) constantAddressMap) of
                                                    Just _ -> ((intLitC, decLitC, strLitC, boolLitC), constantAddressMap)
                                                    _ -> let newConsAddressMap = (Map.insert ("<bool>" ++ (show bool)) boolLitC constantAddressMap)
                                                            in ((intLitC, decLitC, strLitC, boolLitC + 1), newConsAddressMap)
                         _ -> ((intLitC,decLitC, strLitC, boolLitC), constantAddressMap)
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionVarArray _ ((ArrayAccessExpression expression) : []))  = 
                            fillFromExpression literalCounters constantAddressMap expression
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionVarArray _ ((ArrayAccessExpression expression1) : (ArrayAccessExpression expression2) :[])) =
                            fillFromTwoExpressions literalCounters constantAddressMap expression1 expression2
fillFromExpressionAdaptee literalCounters constantAddressMap (ExpressionFuncCall funcCall) =
                            fillFromFunctionCall funcCall literalCounters constantAddressMap

fillFromTwoExpressions :: LiteralCounters -> ConstantAddressMap -> Expression -> Expression -> (LiteralCounters,ConstantAddressMap)
fillFromTwoExpressions literalCounters constantAddressMap exp1 exp2 = let (newLiteralCounters1,constAddressMap1) =
                                                                            fillFromExpression literalCounters constantAddressMap exp1
                                                                      in let (newLiteralCounters2,constAddressMap2) = fillFromExpression newLiteralCounters1 constAddressMap1 exp2
                                                                            in (newLiteralCounters2,(Map.union constAddressMap1 constAddressMap2))
