unit KM_CommonTypes;
interface
uses Classes, SysUtils, KM_Utils, MMSystem;


type
  TKMList = class(TList)
  public
    procedure Clear; override;
  end;


type TKMPointList = class
  public
    Count:integer;
    List:array of TKMPoint; //1..Count
    procedure Clearup; virtual;
    procedure AddEntry(aLoc:TKMPoint); dynamic;
    function RemoveEntry(aLoc:TKMPoint):cardinal; virtual;
    function GetRandom():TKMPoint;
  end;


type TKMPointTagList = class (TKMPointList)
  public
    Tag,Tag2:array of integer; //1..Count
    procedure Clearup; override;
    procedure AddEntry(aLoc:TKMPoint; aTag,aTag2:cardinal); reintroduce;
    function RemoveEntry(aLoc:TKMPoint):cardinal; override;
  end;


{This is custom logging system}
type
  TKMLog = class
  private
    fl:textfile;
    logfile:string;
    PreviousTick:cardinal;
    procedure AddLine(text:string);
    procedure AddLineNoTime(text:string);
  public
    constructor Create(path:string);
    //AppendLog adds the line to Log along with time passed since previous line added
    procedure AppendLog(text:string); overload;
    procedure AppendLog(text:string; num:integer); overload;
    procedure AppendLog(text:string; num:single ); overload;
    procedure AppendLog(num:integer; text:string); overload;
    procedure AppendLog(text:string; Res:boolean); overload;
    procedure AppendLog(a,b:integer); overload;
    //Add line if TestValue=false
    procedure AssertToLog(TestValue:boolean; MessageText:string);
    //AddToLog simply adds the text
    procedure AddToLog(text:string);
  end;

  var
    fLog: TKMLog;

implementation


{Reset log file}
constructor TKMLog.Create(path:string);
begin
  logfile:=path;
  assignfile(fl,logfile);
  rewrite(fl);
  closefile(fl);
  AddToLog('');
  AddToLog('');
  AddToLog('Log is up and running');
end;

{Lines are timestamped, each line invokes file open/close for writing,
meaning no lines will be lost if Remake crashes}
procedure TKMLog.AddLine(text:string);
var Delta:cardinal;
begin
  Delta:=TimeGetTime - PreviousTick;
  PreviousTick:=TimeGetTime;
  if Delta>100000 then Delta:=0; //ommit first usage
  assignfile(fl,logfile);
  append(fl);
  writeln(fl,#9+inttostr(Delta)+'ms'+#9+text);
  closefile(fl);
end;

{Same line but without timestamp}
procedure TKMLog.AddLineNoTime(text:string);
begin
  assignfile(fl,logfile);
  append(fl);
  writeln(fl,#9+#9+text);
  closefile(fl);
end;

procedure TKMLog.AppendLog(text:string);
begin
  AddLine(text);
end;

procedure TKMLog.AppendLog(text:string; num:integer);
begin
  AddLine(text+' '+inttostr(num));
end;

procedure TKMLog.AppendLog(text:string; num:single);
begin
  AddLine(text+' '+FloatToStr(num));
end;

procedure TKMLog.AppendLog(num:integer; text:string);
begin
  AddLine(inttostr(num)+' '+text);
end;

procedure TKMLog.AppendLog(text:string; Res:boolean);
var s:string;
begin
  if Res then s:='done' else s:='fail';
  AddLine(text+' ... '+s);
end;

procedure TKMLog.AppendLog(a,b:integer);
begin
  AddLine(inttostr(a)+' : '+inttostr(b));
end;

procedure TKMLog.AssertToLog(TestValue:boolean; MessageText:string);
begin
  if not TestValue then
  AddLine('ASSERTION FAILED! Msg: ' + MessageText);
  Assert(TestValue, 'ASSERTION FAILED! Msg: ' + MessageText);
end;

procedure TKMLog.AddToLog(text:string);
begin
  AddLineNoTime(text);
end;


{ TKMList }
procedure TKMList.Clear;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do begin
    TObject(Items[I]).Free;
    Items[I]:=nil;
  end;
  inherited;
end;


{ TKMPointList }
procedure TKMPointList.Clearup;
begin
  Count:=0;
  setlength(List,0);
end;


procedure TKMPointList.AddEntry(aLoc:TKMPoint);
begin
  inc(Count);
  if Count>length(List)-1 then setlength(List,Count+32);
  List[Count]:=aLoc;
end;


{Remove point from the list if is there. Return 'true' if succeded}
function TKMPointList.RemoveEntry(aLoc:TKMPoint):cardinal;
var i: integer; Found: boolean;
begin
  Result:=0;
  Found := false;
  for i:=1 to Count do
  begin
    if (KMSamePoint(List[i],aLoc) and (not Found)) then
    begin
      dec(Count);
      Found := true;
      Result:=i;
    end;
    if (Found) and (i < Count) then List[i] := List[i+1];
  end;
end;


function TKMPointList.GetRandom():TKMPoint;
begin
  if Count=0 then Result:=KMPoint(0,0)
             else Result:=List[random(Count)+1];
end;


procedure TKMPointTagList.Clearup;
begin
  inherited;
  setlength(Tag,0);
  setlength(Tag2,0);
end;


procedure TKMPointTagList.AddEntry(aLoc:TKMPoint; aTag,aTag2:cardinal);
begin
  inherited AddEntry(aLoc);
  if Count>length(Tag)-1 then setlength(Tag,Count+32);
  if Count>length(Tag2)-1 then setlength(Tag2,Count+32);
  Tag[Count]:=aTag;
  Tag2[Count]:=aTag2;
end;


function TKMPointTagList.RemoveEntry(aLoc:TKMPoint):cardinal;
var i: integer;
begin
  Result:= inherited RemoveEntry(aLoc);

  for i:=Result to Count-1 do
  begin
    Tag[i] := Tag[i+1];
    Tag2[i] := Tag2[i+1];
  end;
end;


end.
