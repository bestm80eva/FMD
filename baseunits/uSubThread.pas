{
        File: uSubThread.pas
        License: GPLv2
        This unit is a part of Free Manga Downloader
}

unit uSubThread;

{$ifdef fpc}
  {$mode objfpc}
{$endif}
{$H+}

interface

uses
  Classes, SysUtils, Controls, Forms, uBaseUnit, uFMDThread,
  httpsend, blcksock;

type

  { TCheckUpdateThread }
  TCheckUpdateThread = class(TFMDThread)
  protected
    fNewVersionNumber,
    fUpdateURL,
    fChangelog,
    FBtnCheckCaption: String;
    procedure SockOnHeartBeat(Sender: TObject);
    procedure MainThreadUpdate;
    procedure MainThreadSetButton;
    procedure Execute; override;
  public
    CheckStatus: ^Boolean;
    ThreadStatus: ^Boolean;
    destructor Destroy; override;
  end;

  { TSubThread }
  TSubThread = class(TFMDThread)
  protected
    FCheckUpdateThread: TCheckUpdateThread;
    procedure Execute; override;
  public
    CheckUpdate,
    CheckUpdateRunning: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;
  
resourcestring
  RS_NewVersionFound = 'New Version found!';
  RS_CurrentVersion = 'Installed Version';
  RS_LatestVersion = 'Latest Version   ';

implementation

uses
  frmMain, frmUpdateDialog;

{ TCheckUpdateThread }

procedure TCheckUpdateThread.SockOnHeartBeat(Sender: TObject);
begin
  if Terminated then
  begin
    TBlockSocket(Sender).Tag := 1;
    TBlockSocket(Sender).StopFlag := True;
    TBlockSocket(Sender).AbortSocket;
  end;
end;

procedure TCheckUpdateThread.MainThreadUpdate;
begin
  with TUpdateDialogForm.Create(MainForm) do try
    Caption := Application.Title + ' - ' + RS_NewVersionFound;
    with mmLog.Lines do
    begin
      BeginUpdate;
      try
        Clear;
        Add(RS_CurrentVersion + ' : ' + FMD_VERSION_NUMBER);
        Add(RS_LatestVersion + ' : ' + fNewVersionNumber + LineEnding);
        AddText(fChangelog);
      finally
        EndUpdate;
      end;
    end;
    if ShowModal = mrYes then
    begin
      MainForm.DoUpdateFMD := True;
      MainForm.FUpdateURL := fUpdateURL;
      MainForm.itMonitor.Enabled := True;
    end
    else
      MainForm.btCheckVersion.Caption := stUpdaterCheck;
  finally
    Free;
  end;
end;

procedure TCheckUpdateThread.MainThreadSetButton;
begin
  MainForm.btCheckVersion.Caption := FBtnCheckCaption;
end;

procedure TCheckUpdateThread.Execute;
var
  l: TStringList;
  FHTTP: THTTPSend;
  updateFound: Boolean = False;
begin
  ThreadStatus^ := True;
  l := TStringList.Create;
  FHTTP := THTTPSend.Create;
  try
    fNewVersionNumber := FMD_VERSION_NUMBER;
    fUpdateURL := '';
    FBtnCheckCaption := stFavoritesChecking;
    Synchronize(@MainThreadSetButton);
    FHTTP.Sock.OnHeartbeat := @SockOnHeartBeat;
    FHTTP.Sock.HeartbeatRate := SOCKHEARTBEATRATE;
    if not Terminated and
      GetPage(Self, FHTTP, TObject(l), UPDATE_URL + 'update', 3, False) then
      if l.Count > 1 then
      begin
        l.NameValueSeparator := '=';
        if Trim(l.Values['VERSION']) <> FMD_VERSION_NUMBER then
        begin
          fNewVersionNumber := Trim(l.Values['VERSION']);
          fUpdateURL := Trim(l.Values[UpperCase(FMD_TARGETOS)]);
          if fUpdateURL <> '' then
            updateFound := True;
          FHTTP.Clear;
          l.Clear;
          if not Terminated and
            GetPage(Self, FHTTP, TObject(l), UPDATE_URL + 'changelog.txt', 3, False) then
            fChangelog := l.Text;
        end;
      FBtnCheckCaption := stUpdaterCheck;
      Synchronize(@MainThreadSetButton);
    end;
  finally
    FHTTP.Free;
    l.Free;
  end;
  if not Terminated and updateFound then
    Synchronize(@MainThreadUpdate);
end;

destructor TCheckUpdateThread.Destroy;
begin
  CheckStatus^ := False;
  ThreadStatus^ := False;
  inherited Destroy;
end;

{ TSubThread }

procedure TSubThread.Execute;
begin
  MainForm.isSubthread := True;
  try
    if FileExists(fmdDirectory + 'old_updater.exe') then
      DeleteFile(fmdDirectory + 'old_updater.exe');

    if OptionAutoCheckFavStartup then
    begin
      MainForm.FavoriteManager.isAuto := True;
      MainForm.FavoriteManager.isShowDialog := MainForm.cbOptionShowFavoriteDialog.Checked;
      MainForm.FavoriteManager.Run;
    end;

    while not Terminated do
    begin
      if CheckUpdate and (not CheckUpdateRunning) then
      begin
        FCheckUpdateThread := TCheckUpdateThread.Create(True);
        FCheckUpdateThread.CheckStatus := @CheckUpdate;
        FCheckUpdateThread.ThreadStatus := @CheckUpdateRunning;
        FCheckUpdateThread.Start;
      end;

      with MainForm do
      begin
        while (SilentThreadManager.MetaData.Count > 0) and
          (SilentThreadManager.Threads.Count < DLManager.maxDLThreadsPerTask) do
          SilentThreadManager.CheckOut;
      end;
      Sleep(500);
    end;
    if CheckUpdateRunning then
    begin
      FCheckUpdateThread.Terminate;
      FCheckUpdateThread.WaitFor;
    end;
  except
    on E: Exception do
      MainForm.ExceptionHandler(Self, E);
  end;
end;

constructor TSubThread.Create;
begin
  inherited Create(True);
  CheckUpdate := False;
  CheckUpdateRunning := CheckUpdate;
end;

destructor TSubThread.Destroy;
begin
  MainForm.isSubthread := False;
  inherited Destroy;
end;

end.
