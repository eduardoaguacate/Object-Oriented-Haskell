module TypeChecker where 
import Data.Decimal
import DataTypes
import Text.Show.Pretty

import SymbolTable
import ClassSymbolTable
import qualified Data.Map.Strict as Map
import Data.List (intercalate, maximumBy)
import Data.Ord (comparing)

newtype ClassTypeChecker = State ClassSymbolTable

startSemanticAnalysis :: Program -> IO ()
startSemanticAnalysis (Program classList functionList varsList block) =  do 
            let (classSymbolTable, classErrors) = analyzeClasses classList emptyClassSymbolTable
            if (classErrors) 
                then putStrLn $ show "[1] ERROR: Semantic Error in Class Checking."
                else putStrLn $ ppShow $ "[1]: Semantic Class Analysis Passed."
            putStrLn $ ppShow $ classSymbolTable
            let (symbolTable,semanticError) = analyzeVariables varsList globalScope Nothing emptySymbolTable classSymbolTable
            if (semanticError) 
                then putStrLn $ show "[2] ERROR: Semantic Error in Variable Checking."
                else putStrLn $ ppShow $ "[2]: Semantic Variable Analysis Passed."
            putStrLn $ ppShow $ symbolTable

-- Analyze classes regresa una tabla de simbolos de clase y un booleano. Si es true, significa que hubo errores, si es false, no hubo errores
analyzeClasses :: [Class] -> ClassSymbolTable -> (ClassSymbolTable, Bool)
analyzeClasses [] _ = (emptyClassSymbolTable, False) 
analyzeClasses (cl : classes) classSymTab =
                                            -- se obtiene la symbol table de esa clase, donde tiene funciones y atributos
                                            let (varsSymTabForClass,hasErrors) = analyzeClassBlock cl emptySymbolTable classSymTab
                                            in if (hasErrors) then (emptyClassSymbolTable, True)
                                                -- Metemos las variables y funciones de la clase 
                                                else let (newClassSymTab1, hasErrors1) = analyzeClass cl varsSymTabForClass classSymTab
                                                 in if hasErrors1 then (emptyClassSymbolTable, True)
                                                   else let (newClassSymTab2, hasErrors2) = analyzeClasses classes newClassSymTab1
                                                        in if hasErrors2 then (emptyClassSymbolTable, True)
                                                           else ((Map.union newClassSymTab1 newClassSymTab2), False)

analyzeClassBlock :: Class -> SymbolTable -> ClassSymbolTable ->  (SymbolTable, Bool)
analyzeClassBlock (ClassInheritance classIdentifier _ classBlock) symTab classSymTab = analyzeMembersOfClassBlock classBlock classIdentifier defScope symTab classSymTab
analyzeClassBlock (ClassNormal classIdentifier classBlock) symTab classSymTab = analyzeMembersOfClassBlock classBlock classIdentifier defScope symTab classSymTab

analyzeMembersOfClassBlock :: ClassBlock -> ClassIdentifier -> Scope -> SymbolTable -> ClassSymbolTable  -> (SymbolTable,Bool)
analyzeMembersOfClassBlock (ClassBlockNoConstructor classMembers) classIdentifier scp symTab classSymTab = analyzeClassMembers classMembers classIdentifier scp symTab classSymTab
analyzeMembersOfClassBlock (ClassBlock classMembers (ClassConstructor params block)) classIdentifier scp symTab classSymTab = 
                                        let (newSymTab1, hasErrors) = analyzeClassMembers classMembers classIdentifier scp symTab classSymTab
                                        in if (hasErrors == True) then (emptySymbolTable,True)
                                            else let (symTabFunc, hasErrors2) = analyzeFuncParams params emptySymbolTable classSymTab   
                                                in if (hasErrors2 == True) then (emptySymbolTable, True)
                                                    -- Debido a que funciones pueden tener identificadores en sus parametros,
                                                    -- hay que verificar que no interfieran con otros identificadores dentro de la
                                                    -- clase
                                                    else if (Map.size (Map.intersection symTabFunc newSymTab1)) == 0
                                                         then let newSymTab = (Map.insert "_constructor" (SymbolFunction {returnType = (Just (TypeClassId classIdentifier [])), scope = scp, body = block, shouldReturn = False ,isPublic = (Just True), symbolTable = symTabFunc, params = params}) symTab)
                                                                in analyzeClassMembers classMembers classIdentifier scp newSymTab classSymTab
                                                          else (emptySymbolTable, True)                       
-- let (newSymTab2,hasErrors) = analyzeClassMember cm scp newSymTab
--                                             if hasErrors then (emptySymbolTable, True)
--                                                 else let (newSymTab3,hasErrors2) = analyzeMembersOfClassBlock 
--                                                     (Map.union newSymTab2
analyzeClassMembers :: [ClassMember] -> ClassIdentifier -> Scope -> SymbolTable -> ClassSymbolTable -> (SymbolTable, Bool)
analyzeClassMembers [] _ _ _ _ = (emptySymbolTable,False)
analyzeClassMembers (cm : cms) classIdentifier scp symTab classSymbolTable = 
                                                        let (newSymTab, hasErrors) = analyzeClassMember cm classIdentifier scp symTab classSymbolTable
                                                        in if (hasErrors) then (emptySymbolTable,True)
                                                            else let (newSymTab2,hasErrors2) = analyzeClassMembers cms classIdentifier scp newSymTab classSymbolTable
                                                                in if (hasErrors2) then (emptySymbolTable,True)
                                                                    else ((Map.union newSymTab newSymTab2), False)

analyzeClassMember :: ClassMember -> ClassIdentifier -> Scope -> SymbolTable -> ClassSymbolTable -> (SymbolTable, Bool)
analyzeClassMember (ClassMemberAttribute (ClassAttributePublic variable)) classIdentifier scp symTab classSymTab = analyzeVariable variable scp  (Just True) symTab classSymTab
analyzeClassMember (ClassMemberAttribute (ClassAttributePrivate variable)) classIdentifier scp symTab classSymTab = analyzeVariable variable scp  (Just False) symTab classSymTab 
analyzeClassMember (ClassMemberFunction (ClassFunctionPublic function)) classIdentifier scp symTab classSymTab = analyzeFunction function scp (Just True) symTab classSymTab
analyzeClassMember (ClassMemberFunction (ClassFunctionPrivate function)) classIdentifier scp symTab classSymTab = analyzeFunction function scp (Just False) symTab classSymTab

analyzeClass :: Class -> SymbolTable -> ClassSymbolTable -> (ClassSymbolTable, Bool)
analyzeClass (ClassInheritance subClass parentClass classBlock) varSymTab classSymTab = if Map.member subClass classSymTab
                                                                    then (classSymTab, True) -- regresamos que si hay error
                                                                    -- Solo vamos a heredar si la clase padre esta en la tabla de simbolos de clase
                                                                    else if Map.member parentClass classSymTab  
                                                                        then 
                                                                            let newClassSymTable = Map.insert subClass varSymTab classSymTab -- Si si es miembro, entonces si se puede heredar
                                                                            in (newClassSymTable, False) -- No hay error, devolvemos la nueva
                                                                        else (classSymTab,True) -- Si el parent class no es miembro, entonces error, no puedes heredar de una clase no declarada

analyzeClass (ClassNormal classIdentifier classBlock) varSymTab classSymTab = if Map.member classIdentifier classSymTab
                                                                    then (classSymTab, False)
                                                                    else 
                                                                        let newClassSymTable = Map.insert classIdentifier varSymTab classSymTab
                                                                        in (newClassSymTable, False)


analyzeVariables :: [Variable] -> Scope -> Maybe Bool -> SymbolTable -> ClassSymbolTable -> (SymbolTable, Bool)
analyzeVariables [] _ _ _ _ = (emptySymbolTable, False)
analyzeVariables (var : vars) scp isVarPublic symTab classTab = let (newSymTab1, hasErrors1) = analyzeVariable var scp isVarPublic symTab classTab
                                               in if hasErrors1 then (emptySymbolTable, True)
                                               else let (newSymTab2, hasErrors2) = analyzeVariables vars scp isVarPublic newSymTab1 classTab
                                                    in if hasErrors2 then (emptySymbolTable, True)
                                                       else ((Map.union newSymTab1 newSymTab2), False)


analyzeVariable :: Variable -> Scope -> Maybe Bool -> SymbolTable -> ClassSymbolTable -> (SymbolTable, Bool)
analyzeVariable (VariableNoAssignment dataType identifiers) scp isVarPublic symTab classTab = 
    -- Checamos si existe ese tipo
    if (checkTypeExistance dataType classTab) 
        then insertIdentifiers identifiers (SymbolVar {dataType = dataType, scope = scp, isPublic = isVarPublic}) symTab classTab
        else (emptySymbolTable, True) -- No existio esa clase, error
analyzeVariable (VariableAssignmentLiteralOrVariable dataType identifier literalOrVariable) scp isVarPublic symTab classTab =
                                        -- En esta parte nos aseguramos que el tipo este declarado, el literal or variable exista y que la asignacion de tipos de datos sea correcta
                                        if (checkTypeExistance dataType classTab) &&  (checkLiteralOrVariableInSymbolTable literalOrVariable symTab) && (checkDataTypes dataType literalOrVariable symTab)
                                            then insertInSymbolTable identifier (SymbolVar {dataType = dataType, scope = scp, isPublic = isVarPublic}) symTab
                                            else (emptySymbolTable, True)  -- hubo error, entonces regresamos la tabla vacia
analyzeVariable (VariableAssignment1D dataType identifier literalOrVariables) scp isVarPublic symTab classTab = 
                                        -- En esta parte nos aseguramos que la lista de asignaciones concuerde con el tipo de dato declarado
                                        case dataType of
                                            TypePrimitive _ (("[",size,"]") : []) ->  
                                                makeCheckFor1DAssignment size
                                            TypeClassId _ (("[",size,"]") : []) ->  
                                                makeCheckFor1DAssignment size
                                            _ -> (emptySymbolTable, True)
                                        where
                                            makeCheckFor1DAssignment size = if (checkTypeExistance dataType classTab) 
                                                                                && (checkLiteralOrVariablesAndDataTypes dataType literalOrVariables symTab) 
                                                                                && ((length literalOrVariables) <= fromIntegral size)
                                                    then insertInSymbolTable identifier (SymbolVar {dataType = dataType, scope = scp, isPublic = isVarPublic}) symTab
                                                    else (emptySymbolTable, True)  -- hubo error, entonces regresamos la tabla vacia
                                        
analyzeVariable (VariableAssignment2D dataType identifier listOfLiteralOrVariables) scp isVarPublic symTab classTab = 
                                        case dataType of
                                            TypePrimitive _ (("[",sizeRows,"]") : ("[",sizeCols,"]") : []) ->  
                                                makeCheckFor2DAssignment sizeRows sizeCols
                                            TypeClassId _ (("[",sizeRows,"]") : ("[",sizeCols,"]") : []) ->  
                                                makeCheckFor2DAssignment sizeRows sizeCols
                                            _ -> (emptySymbolTable, True)
                                        where
                                            makeCheckFor2DAssignment sizeRows sizeCols = if (checkTypeExistance dataType classTab) && 
                                                                               (checkLiteralOrVariablesAndDataTypes2D dataType listOfLiteralOrVariables symTab)
                                                                               && ((length listOfLiteralOrVariables) <= fromIntegral sizeRows) -- checamos que sea el numero correcto de renglones
                                                                               && ((getLongestList listOfLiteralOrVariables) <= fromIntegral sizeCols)
                                                    then insertInSymbolTable identifier (SymbolVar {dataType = dataType, scope = scp, isPublic = isVarPublic}) symTab
                                                    else (emptySymbolTable, True)  -- hubo error, entonces regresamos la tabla vacia
                                            getLongestList :: [[LiteralOrVariable]] -> Int
                                            getLongestList [] = 0
                                            getLongestList (x : xs) = max (length x) (getLongestList xs) 
analyzeVariable (VariableAssignmentObject dataType identifier (ObjectCreation classIdentifier params)) scp isVarPublic symTab classTab = 
                                        case dataType of
                                            TypePrimitive _ _ -> (emptySymbolTable, True)
                                            -- Checamos si el constructor es del mismo tipo que la clase
                                            TypeClassId classIdentifierDecl _ -> if (classIdentifierDecl == classIdentifier)
                                                                                 -- Checamos los parametros que se mandan con los del constructor
                                                                                 && (checkIfParamsAreCorrect params classIdentifier symTab classTab) 
                                                                                 then insertInSymbolTable identifier (SymbolVar {dataType = dataType, scope = scp, isPublic = isVarPublic}) symTab
                                                                                 else (emptySymbolTable, True)
analyzeVariable (VariableListAssignment (TypeListClassId classIdentifier) identifier (ListAssignmentArray literalOrVariables)) scp isVarPublic symTab classTab = 
                                        -- Checamos si la clase esta declarada
                                         if (checkTypeExistance (TypeClassId classIdentifier []) classTab)
                                         -- Checamos que las asignaciones sean del mismo tipo que la clase
                                         && (checkLiteralOrVariablesAndDataTypes (TypeClassId classIdentifier []) literalOrVariables symTab)
                                            then insertInSymbolTable identifier (SymbolVar {dataType = (TypeListClassId classIdentifier), scope = scp, isPublic = isVarPublic}) symTab
                                            else (emptySymbolTable, True)
analyzeVariable (VariableListAssignment (TypeListPrimitive (PrimitiveInt)) identifier (ListAssignmentRange initial limit)) scp isVarPublic symTab classTab = 
                                         -- Se inserta si y solo si el typelist recibe es un primitive int, o sea, solo si 
                                         -- List of Int 1..2
                                         insertInSymbolTable identifier (SymbolVar {dataType = (TypeListPrimitive (PrimitiveInt)), scope = scp, isPublic = isVarPublic}) symTab
analyzeVariable (VariableListAssignment (TypeListPrimitive (PrimitiveInteger)) identifier (ListAssignmentRange initial limit)) scp isVarPublic symTab classTab = 
                                         -- Se inserta si y solo si el typelist recibe es un primitive int, o sea, solo si 
                                         -- List of Integer 1..2
                                         insertInSymbolTable identifier (SymbolVar {dataType = (TypeListPrimitive (PrimitiveInteger)), scope = scp, isPublic = isVarPublic}) symTab
analyzeVariable _ _ _ _ _  = (emptySymbolTable, True)


analyzeFunction :: Function -> Scope -> Maybe Bool -> SymbolTable -> ClassSymbolTable -> (SymbolTable, Bool)
analyzeFunction (Function identifier (TypeFuncReturnPrimitive primitive) params (Block statements)) scp isPublic symTab classSymTab = 
                    if  (Map.notMember identifier symTab)
                        then let (newFuncSymTab, hasErrors) = (analyzeFuncParams params emptySymbolTable classSymTab)
                                    -- Si hay errores o literalmente hay identificadores que son iguales que otros miembros, error
                                   in if (hasErrors) || ((Map.size (Map.intersection symTab newFuncSymTab)) /= 0) then (emptySymbolTable,True)
                                        else let newSymTabFunc = Map.insert identifier (SymbolFunction {returnType = (Just (TypePrimitive primitive [])), scope = scp, body = (Block statements), shouldReturn = True ,isPublic = isPublic, symbolTable = newFuncSymTab, params = params}) symTab
                                            in let areRetTypesOk = areReturnTypesOk (TypePrimitive primitive []) statements newSymTabFunc newFuncSymTab classSymTab
                                             in if areRetTypesOk == True then (newSymTabFunc,False)
                                                else (emptySymbolTable, True) 
                                -- in  -- if (checkCorrectReturnType (TypeClassId classIdentifier) block newSymTabFunc ) 
                        else (emptySymbolTable, True)
analyzeFunction (Function identifier (TypeFuncReturnClassId classIdentifier) params (Block statements)) scp isPublic symTab classSymTab = 
                if (checkTypeExistance (TypeClassId classIdentifier []) classSymTab)
                    then if (Map.notMember identifier symTab)
                        then let (newFuncSymTab, hasErrors) = (analyzeFuncParams params emptySymbolTable classSymTab)
                                    -- Si hay errores o literalmente hay identificadores que son iguales que otros miembros, error
                                   in if (hasErrors) || ((Map.size (Map.intersection symTab newFuncSymTab)) /= 0) then (emptySymbolTable,True)
                                        else let newSymTabFunc = Map.insert identifier (SymbolFunction {returnType = (Just (TypeClassId classIdentifier [])), scope = scp, body = (Block statements), shouldReturn = True ,isPublic = isPublic, symbolTable = newFuncSymTab, params = params}) symTab
                                          in let areRetTypesOk = areReturnTypesOk (TypeClassId classIdentifier []) statements newSymTabFunc newFuncSymTab classSymTab
                                             in if areRetTypesOk == True then (newSymTabFunc,False)
                                                else (emptySymbolTable, True)-- && analyzeFuncBlock statements newSymTab2 classSymTab
                        else (emptySymbolTable, True)
                    else (emptySymbolTable, True)
    -- Como no regresa nada, no hay que buscar que regrese algo el bloque
analyzeFunction (Function identifier (TypeFuncReturnNothing) params (Block statements)) scp isPublic symTab classSymTab =  
                  if  (Map.notMember identifier symTab)
                        then let (newFuncSymTab, hasErrors) = (analyzeFuncParams params emptySymbolTable classSymTab)
                                    -- Si hay errores o literalmente hay identificadores que son iguales que otros miembros o bien, que el usuario quiere regresar en una funcion nothing
                                   in if (hasErrors) || (length (getReturnStatements statements)) > 0 || ((Map.size (Map.intersection symTab newFuncSymTab)) /= 0) then (emptySymbolTable,True)
                                        else let newSymTabFunc = Map.insert identifier (SymbolFunction {returnType = Nothing, scope = scp, body = (Block statements), shouldReturn = False ,isPublic = isPublic, symbolTable = newFuncSymTab, params = params}) symTab
                                              in (newSymTabFunc,False)
                                -- in  -- if (checkCorrectReturnType (TypeClassId classIdentifier) block newSymTabFunc ) 
                        else (emptySymbolTable, True)

-- analyzeFuncBlock :: [Statement] -> SymbolTable -> ClassSymbolTable -> (SymbolTable,Bool)
-- analyzeFuncBlock [] _ _ = (emptySymbolTable, False)
-- analyzeFuncBlock ((VariableStatement variable) : sts) = 

areReturnTypesOk :: Type -> [Statement] -> SymbolTable -> SymbolTable -> ClassSymbolTable -> Bool
areReturnTypesOk funcRetType statements symTab ownFuncSymTab classTab = 
    let returnList = getReturnStatements statements 
    in if (length returnList) == 0 then False -- Se esperaba que regresara un tipo
        else (checkCorrectReturnTypes funcRetType returnList symTab ownFuncSymTab classTab)

-- Aqui sacamos todos los returns que pueda haber, inclusive si estan en statements anidados
getReturnStatements :: [Statement]  -> [Return]
getReturnStatements [] = []
getReturnStatements ((ReturnStatement returnExp) : sts) = (returnExp) : (getReturnStatements sts)
getReturnStatements ((ConditionStatement (If _ (Block statements))) : sts) = (getReturnStatements statements) ++ (getReturnStatements sts)
getReturnStatements ((ConditionStatement (IfElse _ (Block statements) (Block statementsElse))) : sts) = (getReturnStatements statements) ++ (getReturnStatements statementsElse) ++ (getReturnStatements sts)
getReturnStatements ((CycleStatement (CycleWhile (While _ (Block statements)))) : sts) = (getReturnStatements statements) ++ (getReturnStatements sts)
getReturnStatements ((CycleStatement (CycleFor (For _ _ (Block statements)))) : sts) = (getReturnStatements statements) ++ (getReturnStatements sts)
getReturnStatements (_ : sts) =  (getReturnStatements sts)

analyzeFuncParams :: [(Type,Identifier)] -> SymbolTable -> ClassSymbolTable -> (SymbolTable,Bool)
analyzeFuncParams [] _  _ = (emptySymbolTable, False)
analyzeFuncParams ((dataType,identifier) : rest) symTab classSymTab = 
    let (newSymTab, hasErrors) = analyzeVariable ((VariableNoAssignment dataType [identifier] )) defScope Nothing symTab classSymTab
        in if (hasErrors) then (emptySymbolTable,True)
            else let (newSymTab2, hasErrors2) = analyzeFuncParams rest newSymTab classSymTab
                 in if (hasErrors2 == True) then (emptySymbolTable,True) 
                    else ((Map.union newSymTab newSymTab2), False)



checkCorrectReturnTypes :: Type -> [Return] -> SymbolTable -> SymbolTable -> ClassSymbolTable -> Bool
checkCorrectReturnTypes _ [] _ _ _ = True
checkCorrectReturnTypes  dataType ((ReturnFunctionCall (FunctionCallVar identifier callParams)) : rets) symTab ownFuncSymTab classTab =  
                    case (Map.lookup identifier (Map.union symTab ownFuncSymTab)) of
                        Just (SymbolFunction params returnTypeFunc _ _ _ _ _) -> 
                                        let funcParamTypes = map (\p -> fst p) params
                                        in  case returnTypeFunc of
                                                Just retType -> dataType == retType
                                                                && (compareListOfTypesWithFuncCall funcParamTypes callParams (Map.union symTab ownFuncSymTab))
                                                                && checkCorrectReturnTypes dataType rets symTab ownFuncSymTab classTab
                                                _ -> False           
                        _ -> False
checkCorrectReturnTypes  dataType ((ReturnFunctionCall (FunctionCallObjMem (ObjectMember identifier functionIdentifier) callParams)) : rets) symTab ownFuncSymTab classTab =  
                    case (Map.lookup identifier (Map.union symTab ownFuncSymTab)) of
                        Just (SymbolVar symDataType _ _)  -> 
                                      case symDataType of
                                        TypeClassId classIdentifier _ -> 
                                                    case (Map.lookup classIdentifier classTab) of
                                                        Just symbolTable ->
                                                                case (Map.lookup functionIdentifier symbolTable) of
                                                                    Just (SymbolFunction params returnTypeFunc _ _ _ (Just True) _) ->
                                                                        case returnTypeFunc of
                                                                            Just retType -> retType == dataType
                                                                                && (compareListOfTypesWithFuncCall (map (\p -> fst p) (params)) callParams (Map.union symTab ownFuncSymTab))
                                                                                && checkCorrectReturnTypes dataType rets symTab ownFuncSymTab classTab
                                                                            _ -> False   
                                                                    _ -> False   
                                                        _ -> False
                                        _ -> False
                        _ -> False
checkCorrectReturnTypes  dataType ((ReturnExp (ExpressionLitVar literalOrVariable)) : rets) symTab ownFuncSymTab classTab=  
                                            (checkDataTypes dataType literalOrVariable (Map.union symTab ownFuncSymTab))
                                            && checkCorrectReturnTypes dataType rets symTab ownFuncSymTab classTab
checkCorrectReturnTypes  dataType ((ReturnExp expression) : rets) symTab ownFuncSymTab classTab =  
                                            True && checkCorrectReturnTypes dataType rets symTab ownFuncSymTab classTab-- MARK TODO Expressions

-- checkCorrectReturnType 

compareListOfTypesWithFuncCall :: [Type] -> [Params] -> SymbolTable -> Bool
compareListOfTypesWithFuncCall [] [] _ = True
compareListOfTypesWithFuncCall [] (sp : sps) _ = False
compareListOfTypesWithFuncCall (rpType : rps) [] _ = False
compareListOfTypesWithFuncCall (rpType : rps) (sp : sps) symTab = 
                    case sp of
                        (ParamsExpression (ExpressionLitVar literalOrVariable)) -> 
                               (checkDataTypes rpType literalOrVariable symTab)
                               && (compareListOfTypesWithFuncCall rps sps symTab)
                        (ParamsExpression expression) -> 
                               True -- MARK TODO: Checar que la expresion sea del tipo
                               -- checkDataTypes(dataTypeConstructor,checkExpression(expression))
-- Checamos aqui que la llamada al constructor sea correcta
checkIfParamsAreCorrect :: [Params] -> ClassIdentifier -> SymbolTable -> ClassSymbolTable -> Bool
checkIfParamsAreCorrect sendingParams classIdentifier symTab classTab = 
                                    case (Map.lookup classIdentifier classTab) of
                                        Just symbolTableOfClass -> 
                                                case (Map.lookup "_constructor" symbolTableOfClass) of
                                                    Just (symbolFunc) -> (compareBoth (params symbolFunc) sendingParams)
                                                    Nothing -> True -- MARK TODO : Change to False
                                                where 
                                                    -- sp = sending param
                                                    -- rp = receiving param
                                                    compareBoth :: [(Type,Identifier)] -> [Params] -> Bool
                                                    compareBoth [] [] = True
                                                    compareBoth [] (sp : sps) = False -- Hay mas parametros que se mandan de los que se reciben
                                                    compareBoth (rp : rps) [] = False -- Hay mas en el constructor que de los que se mandan
                                                    compareBoth (rp : rps) (sp : sps) = 
                                                                    case sp of
                                                                        (ParamsExpression (ExpressionLitVar literalOrVariable)) -> 
                                                                               let (dataTypeConstructor,_) = rp
                                                                               in (checkDataTypes dataTypeConstructor literalOrVariable symTab)
                                                                                && compareBoth rps sps
                                                                        (ParamsExpression expression) -> 
                                                                               True -- MARK TODO: Checar que la expresion sea del tipo
                                                                               -- checkDataTypes(dataTypeConstructor,checkExpression(expression))
                                        Nothing -> False 

                 
insertIdentifiers :: [Identifier] -> Symbol -> SymbolTable -> ClassSymbolTable -> (SymbolTable,Bool)
insertIdentifiers [] _ _ _ = (emptySymbolTable, False)
insertIdentifiers (identifier : ids) symbol symTab classTab = let (newSymTab1, hasErrors1) = insertInSymbolTable identifier symbol symTab 
                                            in if hasErrors1 then (symTab, True)
                                               else let (newSymTab2, hasErrors2) = insertIdentifiers ids symbol newSymTab1 classTab
                                                    in if hasErrors2 then (symTab, True)
                                                       else ((Map.union newSymTab1 newSymTab2), False)

insertInSymbolTable :: Identifier -> Symbol -> SymbolTable -> (SymbolTable,Bool)
insertInSymbolTable identifier symbol symTab  = 
                                -- Si esta ese identificador en la tabla de simbolos, entonces regreso error
                                if Map.member identifier symTab
                                  then (emptySymbolTable, True)
                                  else ((Map.insert identifier symbol symTab),False)

-- Aqui checamos que la asignacion de un una lista de literales o variables sea del tipo receptor
checkLiteralOrVariablesAndDataTypes :: Type -> [LiteralOrVariable] -> SymbolTable -> Bool
checkLiteralOrVariablesAndDataTypes _ [] _ = True
checkLiteralOrVariablesAndDataTypes dataType (litVar : litVars) symTab =  
                            if (checkLiteralOrVariableInSymbolTable litVar symTab) &&  (checkArrayAssignment dataType litVar symTab)
                                then checkLiteralOrVariablesAndDataTypes dataType litVars symTab
                                else False -- Alguna literal o variable asignada no existe, o bien, el tipo de dato que se esta asignando no concuerda con la declaracion

checkLiteralOrVariableInSymbolTable :: LiteralOrVariable -> SymbolTable  -> Bool
checkLiteralOrVariableInSymbolTable (VarIdentifier identifier) symTab =  Map.member identifier symTab
checkLiteralOrVariableInSymbolTable _ _= True -- Si es otra cosa que var identifier, entonces regresamos true

checkTypeExistance :: Type -> ClassSymbolTable -> Bool
checkTypeExistance (TypeClassId classIdentifier _) classTab = 
                                                  case (Map.lookup classIdentifier classTab) of
                                                  Just _ -> True -- Si existe esa clase
                                                  _ -> False -- El identificador que se esta asignando no esta en ningun lado
checkTypeExistance _ _ = True -- Todos lo demas regresa true


checkLiteralOrVariablesAndDataTypes2D :: Type -> [[LiteralOrVariable]] -> SymbolTable -> Bool
checkLiteralOrVariablesAndDataTypes2D _ [] _ = True
checkLiteralOrVariablesAndDataTypes2D dataType (listOfLitVars : rest) symTab =  
                            if (checkLiteralOrVariablesAndDataTypes dataType listOfLitVars symTab)  
                                then checkLiteralOrVariablesAndDataTypes2D dataType rest symTab
                                else False -- Alguna literal o variable asignada no existe, o bien, el tipo de dato que se esta asignando no concuerda con la declaracion

-- Aqui checamos si el literal or variable que se esta asignando al arreglo sea del tipo indicado
-- es decir, en Humano [10] humanos = [h1,h2,h3,h4] checa que h1,h2,h3 y h4 sean del tipo humano
checkArrayAssignment :: Type -> LiteralOrVariable -> SymbolTable -> Bool 
checkArrayAssignment (TypePrimitive prim arrayDeclaration) (VarIdentifier identifier) symTab = 
                                case (Map.lookup identifier symTab) of
                                    Just symbol -> 
                                            case (dataType symbol) of
                                                TypePrimitive primId _ -> prim == primId
                                                _ -> False 
                                    _ -> False -- El identificador que se esta asignando no esta en ningun lado
checkArrayAssignment (TypeClassId classIdentifier arrayDeclaration) (VarIdentifier identifier) symTab = 
                                case (Map.lookup identifier symTab) of
                                    Just symbol -> 
                                            case (dataType symbol) of
                                                TypeClassId classId _ -> classId == classIdentifier
                                                _ -> False 
                                    _ -> False -- El identificador que se esta asignando no esta en ningun lado
checkArrayAssignment dataType litOrVar symTab  = checkDataTypes dataType litOrVar symTab



-- Aqui checamos si el literal or variable que se esta dando esta de acuerdo al que se esta asignando! O sea,
-- no es valido decir Double d = 1.22; Money m = d;
checkDataTypes :: Type -> LiteralOrVariable -> SymbolTable -> Bool 
checkDataTypes dType (VarIdentifier identifier) symTab =  
                                case (Map.lookup identifier symTab) of
                                    Just symbol -> (dataType symbol) == dType -- Si son iguales, regresamos true
                                    _ -> False -- El identificador que se esta asignando no esta en ningun lado
checkDataTypes (TypePrimitive (PrimitiveInt) _) (IntegerLiteral _) _  = True
checkDataTypes (TypePrimitive (PrimitiveDouble) _) (DecimalLiteral _) _ = True
checkDataTypes (TypePrimitive (PrimitiveMoney) _) (DecimalLiteral _) _ = True
checkDataTypes (TypePrimitive (PrimitiveString) _) (StringLiteral _) _ = True
checkDataTypes (TypePrimitive (PrimitiveInteger) _) (IntegerLiteral _) _ = True
checkDataTypes _ _ _ = False -- Todo lo demas, falso

checkDataTypesMult :: Type -> LiteralOrVariable -> SymbolTable -> Maybe Primitive 
checkDataTypesMult dType (VarIdentifier identifier) symTab =  
                                case (Map.lookup identifier symTab) of
                                    Just symbol -> if (dataType symbol) == dType
                                                        then symbol -- Si son iguales, regresamos true
checkDataTypesMult (TypePrimitive (PrimitiveInt) _) (IntegerLiteral _) _  = PrimitiveInt
checkDataTypesMult (TypePrimitive (PrimitiveDouble) _) (DecimalLiteral _) _ = PrimitiveDouble
checkDataTypesMult (TypePrimitive (PrimitiveMoney) _) (DecimalLiteral _) _ = PrimitiveMoney
checkDataTypesMult (TypePrimitive (PrimitiveInteger) _) (IntegerLiteral _) _ = PrimitiveInteger
checkDataTypesMult (TypePrimitive (PrimitiveInteger) _) (DecimalLiteral _) _ = PrimitiveDouble
checkDataTypesMult (TypePrimitive (PrimitiveInt) _) (DecimalLiteral _) _ = PrimitiveDouble
checkDataTypesMult (TypePrimitive (PrimitiveMoney) _) (IntegerLiteral _) _ = PrimitiveMoney
checkDataTypesMult (TypePrimitive (PrimitiveDouble) _) (IntegerLiteral _) _ = PrimitiveDouble
checkDataTypesMult _ _ _ = False -- Todo lo demas, falso

checkDataTypesRel :: Type -> LiteralOrVariable -> SymbolTable -> Maybe Primitive 
checkDataTypesRel dType (VarIdentifier identifier) symTab =  
                                case (Map.lookup identifier symTab) of
                                    Just symbol -> if (dataType symbol) == dType
                                                        then PrimitiveBool -- Si son iguales, regresamos true
checkDataTypesRel (TypePrimitive (PrimitiveBool) _) False  = PrimitiveBool
checkDataTypesRel (TypePrimitive (PrimitiveInt) _) True  = PrimitiveBool
checkDataTypesRel (TypePrimitive (PrimitiveInt) _) (IntegerLiteral _) _  = PrimitiveBool
checkDataTypesRel (TypePrimitive (PrimitiveDouble) _) (DecimalLiteral _) _ = PrimitiveBool
checkDataTypesRel (TypePrimitive (PrimitiveMoney) _) (DecimalLiteral _) _ = PrimitiveBool
checkDataTypesRel (TypePrimitive (PrimitiveInteger) _) (IntegerLiteral _) _ = PrimitiveBool
checkDataTypesRel (TypePrimitive (PrimitiveInteger) _) (DecimalLiteral _) _ = PrimitiveBool
checkDataTypesRel (TypePrimitive (PrimitiveInt) _) (DecimalLiteral _) _ = PrimitiveBool
checkDataTypesRel (TypePrimitive (PrimitiveMoney) _) (IntegerLiteral _) _ = PrimitiveBool
checkDataTypesRel (TypePrimitive (PrimitiveDouble) _) (IntegerLiteral _) _ = PrimitiveBool
checkDataTypesRel _ _ _ = False -- Todo lo demas, falso

checkDataTypesMOD :: Type -> LiteralOrVariable -> SymbolTable -> Maybe Primitive 
checkDataTypesMOD dType (VarIdentifier identifier) symTab =  
                                case (Map.lookup identifier symTab) of
                                    Just symbol -> if (dataType symbol) == dType && symbol == PrimitiveInt
                                                        then PrimitiveInt -- Si son iguales, regresamos true

checkDataTypesMOD (TypePrimitive (PrimitiveInt) _) (IntegerLiteral _) _  = PrimitiveInt
checkDataTypesMOD (TypePrimitive (PrimitiveInteger) _) (IntegerLiteral _) _ = PrimitiveInteger
checkDataTypesMOD _ _ _ = False -- Todo lo demas, falso

