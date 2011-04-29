unit KM_NetClient;
{$I KaM_Remake.inc}
interface
uses Classes, SysUtils, KM_NetClientOverbyte;


{ Contains basic items we need for smooth Net experience:

    - connect to server
    - signal if we have successfully connected to server
    - signal if we could not connect to server

    - disconnect from server (always successfull)
    - signal if we were forcefully disconnected by server

    - send binary data to other server clients
    - recieve binary data from other server clients

    - optionaly report non-important status messages

}
type
  TKMNetClient = class
  private
    fClient:TKMNetClientOverbyte;
    fConnected:boolean;

    fOnConnectSucceed:TNotifyEvent;
    fOnConnectFailed:TGetStrProc;
    fOnForcedDisconnect:TGetStrProc;
    fOnRecieveData:TNotifyDataEvent;
    fOnStatusMessage:TGetStrProc;
    procedure Error(const S: string);
    procedure ConnectSucceed(Sender: TObject);
    procedure ConnectFailed(const S: string);
    procedure ForcedDisconnect(Sender: TObject);
    procedure RecieveData(aData:pointer; aLength:cardinal);
  public
    constructor Create;
    destructor Destroy; override;

    procedure ConnectTo(const aAddress:string; const aPort:string); //Try to connect to server
    property OnConnectSucceed:TNotifyEvent write fOnConnectSucceed; //Signal success
    property OnConnectFailed:TGetStrProc write fOnConnectFailed; //Signal fail and text description

    procedure Disconnect; //Disconnect from server
    property OnForcedDisconnect:TGetStrProc write fOnForcedDisconnect; //Signal we were forcelly disconnected

    procedure SendText(const aData:string); //For now we use just plain text
    property OnRecieveData:TNotifyDataEvent write fOnRecieveData;
    procedure SendData(aData:pointer; aLength:cardinal);

    property OnStatusMessage:TGetStrProc write fOnStatusMessage;
  end;


implementation


constructor TKMNetClient.Create;
begin
  Inherited;
  fClient := TKMNetClientOverbyte.Create;
  fConnected := false;
end;


destructor TKMNetClient.Destroy;
begin
  fClient.Free;
  Inherited;
end;


procedure TKMNetClient.Error(const S: string);
begin
  if Assigned(fOnStatusMessage) then fOnStatusMessage('Client: Error '+S);
end;


procedure TKMNetClient.ConnectTo(const aAddress:string; const aPort:string);
begin
  fClient.OnError := Error;
  fClient.OnConnectSucceed := ConnectSucceed;
  fClient.OnConnectFailed := ConnectFailed;
  fClient.OnSessionDisconnected := ForcedDisconnect;
  fClient.OnRecieveData := RecieveData;
  fClient.ConnectTo(aAddress, aPort);
  if Assigned(fOnStatusMessage) then fOnStatusMessage('Client: Connecting..');
end;


procedure TKMNetClient.ConnectSucceed(Sender: TObject);
begin
  fConnected := true;
  if Assigned(fOnStatusMessage) then fOnStatusMessage('Client: Connected');
  fOnConnectSucceed(Self);
end;


procedure TKMNetClient.ConnectFailed(const S: string);
begin
  fConnected := false;
  if Assigned(fOnStatusMessage) then fOnStatusMessage('Client: Connection failed. '+S);
  fOnConnectFailed(S);
end;


procedure TKMNetClient.Disconnect;
begin
  fConnected := false;
  fClient.Disconnect;
end;


//Happens in following cases:
//  - when we deliberately disconnect
//  - when connection failed
//  - when server disconnects us
procedure TKMNetClient.ForcedDisconnect(Sender: TObject);
begin
  if fConnected then
  begin
    if Assigned(fOnStatusMessage) then fOnStatusMessage('Client: Forced disconnect');
    fOnForcedDisconnect('9');
  end;
  fConnected := false;
end;


procedure TKMNetClient.SendText(const aData:string);
begin
  SendData(@aData[1], length(aData));
end;


procedure TKMNetClient.SendData(aData:pointer; aLength:cardinal);
begin
  fClient.SendData(@aLength, SizeOf(aLength));
  fClient.SendData(aData, aLength);
  fClient.SendData(@aLength, SizeOf(aLength)); //Fail-check
end;


//Split recieved data into single packets
//todo: handle partial chunks
procedure TKMNetClient.RecieveData(aData:pointer; aLength:cardinal);
var ReadCount,PacketLength,Check:Cardinal;
begin
  ReadCount := 0;
  while (aLength > ReadCount) do
  begin
    PacketLength := PCardinal(Cardinal(aData)+ReadCount)^;
    inc(ReadCount, 4);
    fOnRecieveData(Pointer(Cardinal(aData)+ReadCount), PacketLength);
    inc(ReadCount, PacketLength);
    Check := PInteger(Cardinal(aData)+ReadCount)^;
    inc(ReadCount, 4);
    Assert(PacketLength=Check);
  end;
end;


end.
