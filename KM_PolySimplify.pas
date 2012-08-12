unit KM_PolySimplify;
interface
uses
  KM_Points;


type
  TKMNodesArray = record
    Count: Integer;
    Nodes: TKMPointArray;
  end;

  TKMShapesArray = record
    Count: Integer;
    Shape: array of TKMNodesArray;
  end;


//Simplify shapes by removing unnecessary points from straight lines
procedure SimplifyStraights(const aIn: TKMShapesArray; var aOut: TKMShapesArray);

//Simplify shapes by removing points within aError
procedure SimplifyShapes(const aIn: TKMShapesArray; var aOut: TKMShapesArray; aError: Single; aRect: TKMRect);

//If resulting outlines have too long edges insert additional points there
procedure AddIntermediateNodes(var aArray: TKMShapesArray; aMaxSpan: Byte);

procedure ForceOutlines(var aTriMesh: TKMTriMesh; fSimpleOutlines: TKMShapesArray);

procedure RemoveObstaclePolies(var aTriMesh: TKMTriMesh; fSimpleOutlines: TKMShapesArray);

//Remove anything that is outside bounds
procedure RemoveFrame(var aTriMesh: TKMTriMesh);

//Remove anything that is outside bounds
procedure RemoveDegenerates(var aTriMesh: TKMTriMesh);

implementation
uses KromUtils;


procedure SimplifyStraights(const aIn: TKMShapesArray; var aOut: TKMShapesArray);
  procedure SimplifyStraights2(const aIn: TKMNodesArray; var aOut: TKMNodesArray);
  var K: Integer; P0, P1, P2: Integer;
  begin
    //Reserve space for worst case when nothing gets optimized
    SetLength(aOut.Nodes, aIn.Count);

    for K := 0 to aIn.Count - 1 do
    begin
      P0 := (K - 1 + aIn.Count) mod aIn.Count;
      P1 := K;
      P2 := (K + 1) mod aIn.Count;
      if ((aIn.Nodes[P0].X <> aIn.Nodes[P1].X) or (aIn.Nodes[P1].X <> aIn.Nodes[P2].X))
      and ((aIn.Nodes[P0].Y <> aIn.Nodes[P1].Y) or (aIn.Nodes[P1].Y <> aIn.Nodes[P2].Y)) then
      begin
        aOut.Nodes[aOut.Count] := aIn.Nodes[K];
        Inc(aOut.Count);
      end;
    end;

    //Trim to actual length
    SetLength(aOut.Nodes, aOut.Count);
  end;

var I: Integer;
begin
  SetLength(aOut.Shape, aIn.Count);

  for I := 0 to aIn.Count - 1 do
    SimplifyStraights2(aIn.Shape[I], aOut.Shape[I]);

  aOut.Count := aIn.Count;
end;


function VectorDiff(const A, B: TKMPointF): TKMPointF;
begin
  Result.X := A.X - B.X;
  Result.Y := A.Y - B.Y;
end;


function DotProduct(const A, B: TKMPointF): Single;
begin
  Result := A.X * B.X + A.Y * B.Y;
end;


function DistanceSqr(const A, B: TKMPointF): Single;
begin
  Result := Sqr(A.X - B.X) + Sqr(A.Y - B.Y);
end;


procedure Simplify(aErrorSqr: Single; const aInput: array of TKMPointI; var aKeep: array of Boolean; aFrom, aTo: Integer);
var
  I: Integer;
  MaxDistI: Integer;
  MaxDistSqr: Single;
  NodeDistSqr, TestDot, Tmp: Single;
  DistSqr: Single;
  Node1, Node2: TKMPointF;
  TestPos, NodeVect, TestVect: TKMPointF;
  TestP: TKMPointF;
begin
  //There is nothing to simplify
  if aTo <= aFrom + 1 then Exit;

  Node1 := KMPointF(aInput[aFrom]);
  Node2 := KMPointF(aInput[aTo]);
  NodeVect := VectorDiff(Node2, Node1);
  NodeDistSqr := DistanceSqr(Node2, Node1);
  MaxDistI := 0;
  MaxDistSqr := 0;

  //Check all points and pick farthest away
  for I := aFrom + 1 to aTo - 1 do
  begin
    TestP := KMPointF(aInput[I]);

    TestVect := VectorDiff(TestP, Node1);
    TestDot := DotProduct(TestVect, NodeVect);

    //Calculate distance to segment
    if TestDot <= 0 then
      DistSqr := DistanceSqr(TestP, Node1)
    else
    if TestDot >= NodeDistSqr then
      DistSqr := DistanceSqr(TestP, Node2)
    else
    begin
      if NodeDistSqr <> 0 then
        Tmp := TestDot / NodeDistSqr
      else
        Tmp := 0;
      TestPos.X := Node1.X + Tmp * NodeVect.X;
      TestPos.Y := Node1.Y + Tmp * NodeVect.Y;
      DistSqr := DistanceSqr(TestP, TestPos);
    end;

    //Pick farthest point
    if DistSqr > MaxDistSqr then
    begin
      MaxDistI  := I;
      MaxDistSqr := DistSqr;
    end;
  end;

  //See if we need to split once again
  if MaxDistSqr > aErrorSqr then
  begin
    aKeep[MaxDistI] := True;

    Simplify(aErrorSqr, aInput, aKeep, aFrom, MaxDistI);
    Simplify(aErrorSqr, aInput, aKeep, MaxDistI, aTo);
  end;
end;


//Based on Douglas-Peucker algorithm for polyline simplification
//  aError - max allowed distance between resulting line and removed points
function PolySimplify(aError: Single; aRect: TKMRect; const aInput: TKMPointArray; var aOutput: TKMPointArray): Integer;
const MAX_LOOPS = 5;
var
  I, N: Integer;
  Prev: Integer;
  Keep: array of Boolean;
  Loops: Byte;
  Err: Single;
begin
  Result := 0;

  //See if there's nothing to simplify
  if Length(aInput) < 4 then Exit;
  //If loop length is < Tolerance
  //  return 0
  //else
  //  return loop intact

  N := Length(aInput);
  Assert((aInput[0].X = aInput[N-1].X) and (aInput[0].Y = aInput[N-1].Y),
         'We need shape to be closed to properly process as a series of polylines');

  SetLength(Keep, N);
  for I := 0 to N - 1 do
    Keep[I] := False;

  //We split loop in half and simplify both segments independently as two convex
  //lines. That is because algo is aimed at polyline, not polyloop
  Keep[0] := True;
  Keep[N div 2] := True;
  Keep[N - 1] := True;

  //Keep more nodes on edges
  for I := 0 to N - 1 do
  if (aInput[I].X = aRect.Left) or (aInput[I].Y = aRect.Top)
  or (aInput[I].X = aRect.Right) or (aInput[I].Y = aRect.Bottom) then
    Keep[I] := True;

  //Try hard to keep at leaft 4 points in the outline (first and last are the same, hence 4, not 3)
  //With each loop decrease allowed error
  Loops := 0;
  repeat
      Result := 0;
      if (1 - MAX_LOOPS * Loops) <> 0 then
        Err := Sqr(aError) / (1 - MAX_LOOPS * Loops)
      else 
        Err := 0;

      Prev := 0;
      for I := 1 to N - 1 do
      if Keep[I] then
      begin
        //We use Sqr values for all comparisons for speedup
        Simplify(Err, aInput, Keep, Prev, I);
        Prev := I;
      end;

      //Fill resulting array with preserved points
      for I := 0 to N - 1 do
      if Keep[I] then
      begin
        aOutput[Result] := aInput[I];
        Inc(Result);
      end;

    Inc(Loops);
  until(Result > 3) or (Loops > MAX_LOOPS);
end;


procedure SimplifyShapes(const aIn: TKMShapesArray; var aOut: TKMShapesArray; aError: Single; aRect: TKMRect);
var I: Integer;
begin
  SetLength(aOut.Shape, aIn.Count);

  for I := 0 to aIn.Count - 1 do
  begin
    //Duplicate last point so that Douglas-Peucker could work on loop as 2 polylines
    SetLength(aIn.Shape[I].Nodes, aIn.Shape[I].Count + 1);
    aIn.Shape[I].Nodes[aIn.Shape[I].Count] := aIn.Shape[I].Nodes[0];
    Inc(aIn.Shape[I].Count);

    //Reserve space for worst case when all points are kept
    SetLength(aOut.Shape[I].Nodes, aIn.Shape[I].Count);
    aOut.Shape[I].Count := PolySimplify(aError, aRect, aIn.Shape[I].Nodes, aOut.Shape[I].Nodes);

    //Cut last point since it duplicates 0
    Dec(aOut.Shape[I].Count);
    SetLength(aOut.Shape[I].Nodes, aOut.Shape[I].Count);
  end;
  aOut.Count := aIn.Count;
end;


//If resulting outlines have too long edges insert additional points there
procedure AddIntermediateNodes(var aArray: TKMShapesArray; aMaxSpan: Byte);
var
  I,K,L: Integer;
  X1,X2,Y1,Y2: Word;
  M: Byte;
begin
  for I := 0 to aArray.Count - 1 do
  with aArray.Shape[I] do
  begin
    K := 0;
    repeat
      X1 := Nodes[K].X;
      Y1 := Nodes[K].Y;
      X2 := Nodes[(K + 1) mod Count].X;
      Y2 := Nodes[(K + 1) mod Count].Y;
      M := Round(Sqrt(Sqr(X1 - X2) + Sqr(Y1 - Y2)));
      if M > aMaxSpan then
      begin
        M := Round(M / aMaxSpan);
        SetLength(Nodes, Count + M);

        if Count - 1 <> K then
          Move(Nodes[K+1], Nodes[K+1+M], SizeOf(Nodes[K]) * (Count - 1 - K));

        for L := 0 to M - 1 do
        begin
          Nodes[K+1+L].X := Round(X1 +(X2 - X1) / (M+1) * (L+1));
          Nodes[K+1+L].Y := Round(Y1 +(Y2 - Y1) / (M+1) * (L+1));
        end;

        Inc(Count, M);
      end;
      Inc(K);
    until(K >= Count);
  end;
end;


procedure ForceEdge(var aTriMesh: TKMTriMesh; X1,Y1,X2,Y2: Integer);
var
  I, K, L: Integer;
  Vertice1, Vertice2: Integer;
  Intersect: Boolean;
  Edges: array [0..1] of array of SmallInt;
  Nedge: LongInt;
begin
  with aTriMesh do
  begin
    Vertice1 := -1;
    Vertice2 := -1;
    //Find vertices
    for I := 0 to High(Vertices) do
    begin
      if (x1 = Vertices[I].x) and (y1 = Vertices[I].y) then
        Vertice1 := I;
      if (x2 = Vertices[I].x) and (y2 = Vertices[I].y) then
        Vertice2 := I;
      if (Vertice1 <> -1) and (Vertice2 <> -1) then
        Break;
    end;

    //Exit early if that edge exists
    for I := 0 to High(Polygons) do
    if ((Vertice1 = Polygons[I,0]) and (Vertice2 = Polygons[I,1]))
    or ((Vertice1 = Polygons[I,1]) and (Vertice2 = Polygons[I,2]))
    or ((Vertice1 = Polygons[I,2]) and (Vertice2 = Polygons[I,0])) then
      Exit;

    SetLength(Edges[0], 10000);
    SetLength(Edges[1], 10000);

    //Find triangles we cross
    I := 0;
    Nedge := 0;
    repeat
      //Test each Polygons for intersection with the Edge

      //Eeach test checks if Edge and Polygons edge intersect
      //Edges intersect if 2 polygons made on them are facing different ways

      Intersect :=
           SegmentsIntersect(x1, y1, x2, y2, Vertices[Polygons[I,0]].X,  Vertices[Polygons[I,0]].Y, Vertices[Polygons[I,1]].X,  Vertices[Polygons[I,1]].Y)
        or SegmentsIntersect(x1, y1, x2, y2, Vertices[Polygons[I,1]].X,  Vertices[Polygons[I,1]].Y, Vertices[Polygons[I,2]].X,  Vertices[Polygons[I,2]].Y)
        or SegmentsIntersect(x1, y1, x2, y2, Vertices[Polygons[I,2]].X,  Vertices[Polygons[I,2]].Y, Vertices[Polygons[I,0]].X,  Vertices[Polygons[I,0]].Y);

      //Cut the Polygons
      if Intersect then
      begin
        //Save triangles edges
        Edges[0, Nedge + 0] := Polygons[I,0];
        Edges[1, Nedge + 0] := Polygons[I,1];
        Edges[0, Nedge + 1] := Polygons[I,1];
        Edges[1, Nedge + 1] := Polygons[I,2];
        Edges[0, Nedge + 2] := Polygons[I,2];
        Edges[1, Nedge + 2] := Polygons[I,0];
        Nedge := Nedge + 3;
        //Move last Polygons to I
        Polygons[I,0] := Polygons[High(Polygons),0];
        Polygons[I,1] := Polygons[High(Polygons),1];
        Polygons[I,2] := Polygons[High(Polygons),2];
        Dec(I);
        SetLength(Polygons, Length(Polygons) - 1);
      end;

      Inc(I);
    until (I >= Length(Polygons));

    //Remove duplicate edges and leave only outline
    for I := 0 to Nedge - 1 do
    if not (Edges[0, I] = -1) and not (Edges[1, I] = -1) then
    for K := I + 1 to Nedge - 1 do
    if not (Edges[0, K] = -1) and not (Edges[1, K] = -1) then
    if (Edges[0, I] = Edges[1, K]) and (Edges[1, I] = Edges[0, K]) then
    begin
      Edges[0, I] := -1;
      Edges[1, I] := -1;
      Edges[0, K] := -1;
      Edges[1, K] := -1;
    end;

    //Assemble two polygons on Edge sides
    if Nedge > 0 then
    begin
      //Pick 1st edge and loop from it till Edge vertice
      L := Vertice1;
      repeat
        for K := 0 to Nedge - 1 do
        if (Edges[0, K] = L) then
        begin
          SetLength(Polygons, Length(Polygons) + 1);
          Polygons[High(Polygons),0] := Vertice2;
          Polygons[High(Polygons),1] := Edges[0, K];
          Polygons[High(Polygons),2] := Edges[1, K];
          L := Edges[1, K];
          Break;
        end;
      until(L = Vertice2);
      L := Vertice2;
      repeat
        for K := 0 to Nedge - 1 do
        if (Edges[0, K] = L) then
        begin
          SetLength(Polygons, Length(Polygons) + 1);
          Polygons[High(Polygons),0] := Vertice1;
          Polygons[High(Polygons),1] := Edges[0, K];
          Polygons[High(Polygons),2] := Edges[1, K];
          L := Edges[1, K];
          Break;
        end;
      until(L = Vertice1);
    end;

  end;
end;


procedure ForceOutlines(var aTriMesh: TKMTriMesh; fSimpleOutlines: TKMShapesArray);
var
  I,K: Integer;
begin
  for I := 0 to fSimpleOutlines.Count - 1 do
  with fSimpleOutlines.Shape[I] do
    for K := 0 to Count - 1 do
      ForceEdge(aTriMesh, Nodes[K].X, Nodes[K].Y, Nodes[(K + 1) mod Count].X, Nodes[(K + 1) mod Count].Y);
end;


procedure RemoveObstacle(var aTriMesh: TKMTriMesh; aNodes: TKMPointArray);
var
  I, K, L, M: Integer;
  VCount: Integer;
  Indexes: array of Integer;
  B: Boolean;
begin
  with aTriMesh do
  begin
    VCount := Length(aNodes);
    SetLength(Indexes, VCount);

    //Find Indexes
    for I := 0 to High(Vertices) do
    for K := 0 to VCount - 1 do
    if (aNodes[K].X = Vertices[I].x) and (aNodes[K].Y = Vertices[I].y) then
      Indexes[K] := I;

    //Find Indexes
    I := 0;
    repeat
      B := True;
      for K := 0 to VCount - 1 do
      if B and (Indexes[K] = Polygons[I,0]) then
        for L := K+1 to K+VCount - 2 do
        if B and (Indexes[L mod VCount] = Polygons[I,1]) then
          for M := L+1 to K+VCount - 1 do
          if B and (Indexes[M mod VCount] = Polygons[I,2]) then
          //Cut the triangle
          begin
            //Move last triangle to I
            Polygons[I,0] := Polygons[High(Polygons),0];
            Polygons[I,1] := Polygons[High(Polygons),1];
            Polygons[I,2] := Polygons[High(Polygons),2];
            Dec(I);
            SetLength(Polygons, Length(Polygons) - 1);
            B := False;
          end;
      Inc(I);
    until(I >= Length(Polygons));

    //Delete tris that lie on the outlines edge (direction is important)
    I := 0;
    repeat
      for K := 0 to VCount - 1 do
      if (Indexes[K] = Polygons[I,0]) and (Indexes[(K+1) mod VCount] = Polygons[I,1])
      or (Indexes[K] = Polygons[I,1]) and (Indexes[(K+1) mod VCount] = Polygons[I,2])
      or (Indexes[K] = Polygons[I,2]) and (Indexes[(K+1) mod VCount] = Polygons[I,0]) then
      //Cut the triangle
      begin
        //Move last triangle to I
        Polygons[I,0] := Polygons[High(Polygons),0];
        Polygons[I,1] := Polygons[High(Polygons),1];
        Polygons[I,2] := Polygons[High(Polygons),2];
        Dec(I);
        SetLength(Polygons, Length(Polygons) - 1);
        Break;
      end;
      Inc(I);
    until(I >= Length(Polygons));
  end;
end;


procedure RemoveObstaclePolies(var aTriMesh: TKMTriMesh; fSimpleOutlines: TKMShapesArray);
var
  I: Integer;
begin
  for I := 0 to fSimpleOutlines.Count - 1 do
  with fSimpleOutlines.Shape[I] do
    RemoveObstacle(aTriMesh, Nodes);
end;


//Remove anything that is outside bounds
procedure RemoveFrame(var aTriMesh: TKMTriMesh);
var I: Integer;
begin
  I := 0;
  with aTriMesh do
  repeat
    if (Polygons[I,0] < 4)
    or (Polygons[I,1] < 4)
    or (Polygons[I,2] < 4) then
    //Cut the triangle
    begin
      //Move last triangle to I
      Polygons[I,0] := Polygons[High(Polygons),0];
      Polygons[I,1] := Polygons[High(Polygons),1];
      Polygons[I,2] := Polygons[High(Polygons),2];
      Dec(I);
      SetLength(Polygons, Length(Polygons) - 1);
    end;
    Inc(I);
  until(I >= Length(Polygons));
end;


//Remove anything that is outside bounds
procedure RemoveDegenerates(var aTriMesh: TKMTriMesh);
var I: Integer;
begin
  I := 0;
  with aTriMesh do
  repeat
    if (Polygons[I,0] = Polygons[I,1])
    or (Polygons[I,1] = Polygons[I,2])
    or (Polygons[I,2] = Polygons[I,0]) then
    //Cut the triangle
    begin
      //Move last triangle to I
      Polygons[I,0] := Polygons[High(Polygons),0];
      Polygons[I,1] := Polygons[High(Polygons),1];
      Polygons[I,2] := Polygons[High(Polygons),2];
      Dec(I);
      SetLength(Polygons, Length(Polygons) - 1);
    end;
    Inc(I);
  until(I >= Length(Polygons));
end;


end.