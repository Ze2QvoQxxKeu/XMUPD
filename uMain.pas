unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, IdBaseComponent, IdComponent,
  IdTCPConnection, IdTCPClient, IdHTTP, Vcl.StdCtrls, IdIOHandler, IdIOHandlerSocket,
  IdIOHandlerStack, IdSSL, IdSSLOpenSSL, IdHeaderList, System.Zip;

type
  TfMain = class(TForm)
    xmhttp1: TIdHTTP;
    lbPlugins: TListBox;
    Button1: TButton;
    xmssl1: TIdSSLIOHandlerSocketOpenSSL;
    procedure FormCreate(Sender: TObject);
    procedure lbPluginsClick(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure HeaderOnly(Sender: TObject; AHeaders: TIdHeaderList; var VContinue: Boolean);
  private
  public
    { Public declarations }
  end;

var
  fMain: TfMain;

implementation

{$R *.dfm}

uses
  Winapi.ShellAPI, System.Generics.Defaults, System.Generics.Collections,
  System.RegularExpressions, System.IniFiles, System.IOUtils;

const
  USER_AGENT =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:70.0) Gecko/20100101 Firefox/70.0';
  INI_SECTION = 'XMUPD';
  INI_PLUGINS = 'Plugins';

type
  TDLItemType = (itUnknown, itSkin, itPlugin, itArchivePlugin);

  TDLItem = packed record
    url: string;
    Name: string;
    itype: TDLItemType;
    SIZE: Int64;
    Date: TDateTime;
  public
    procedure Clear;
  end;

  TDLItems = TList<TDLItem>;

  TIniFile = class(System.IniFiles.TIniFile)
    function ReadInteger(const Section, Ident: string; Default: Integer): Integer;
      override;
  end;

  TForumItem = packed record
    id: Integer;
    url: string;
  end;

const
  forum: packed array[0..1] of TForumItem = ((
    id: 8807;
    url: 'https://github.com/schellingb/xmp-wavis'
  ), (
    id: 8808;
    url: 'https://github.com/schellingb/xmp-coverart'
  ));

var
  config: TIniFile;
  plugins: TDLItems;

procedure TfMain.Button1Click(Sender: TObject);
begin
//  Caption := lbPlugins.Items.Count.ToString
  ShellExecute(Handle, 'open', 'https://github.com/Ze2QvoQxxKeu/XMUPD', nil, nil,
    SW_SHOWNORMAL);
end;

function UrlByForumId(id: Integer): string;
var
  i: TForumItem;
begin
  Result := EmptyStr;
  for i in forum do
    if i.id = id then
    begin
      Result := i.url;
      Break;
    end;
end;

procedure TfMain.FormCreate(Sender: TObject);
begin
  TThread.CreateAnonymousThread(
    procedure()
    var
      i, j, h: Integer;
      m, z, q: TMatch;
      p: TDLItem;
      xmhttp: TIdHTTP;
      xmssl: TIdSSLIOHandlerSocketOpenSSL;
      buffer: string;
      output: TMemoryStream;
      SubDir: string;
      xmpzip: string;
    begin
      SubDir := ExtractFilePath(ParamStr(0)) + 'data\';
      xmhttp := TIdHTTP.Create(nil);
      xmssl := TIdSSLIOHandlerSocketOpenSSL.Create(nil);
      xmssl.SSLOptions.Method := sslvTLSv1_2;
      xmhttp.IOHandler := xmssl;
      output := TMemoryStream.Create;
      with TStringList.Create do
      try
        Text := xmhttp.Get('https://www.un4seen.com/xmplay.html');
        with TRegEx.Match(Text, 'href="download\.php\?(xmplay[^"]+)"') do
          if Success then
            xmpzip := Groups[1].Value;
        j := 0;
        for i := 0 to Pred(Count) do
          case j of
            0:
              if Strings[i].Contains('class=head><span>Plugins') then
                Inc(j);
            1:
              if Strings[i].Contains('<table') then
              begin
                Inc(j);
                //Insert(Succ(i), 'href="stuff/xmplay.exe"><img=>=>=>=>XMPlay<');
                Insert(Succ(i), 'href="download.php?' + xmpzip + '"><img=>=>=>=>XMPlay<');
                Insert(Succ(i),
                  'href="stuff/xmp-asio.dll"><img=>=>=>=>ASIO output plugin<');
                Insert(Succ(i),
                  'href="stuff/xmp-ds.dll"><img=>=>=>=>DirectSound output plugin<');
                Insert(Succ(i), 'href="stuff/xmp-lha.dll"><img=>=>=>=>LHA archive plugin<');
              end;
            2:
              if Strings[i].Contains('</table') then
              begin
                Inc(j);
              end
              else
              begin
                m := TRegEx.Match(Strings[i],
                  'href="(download|forum|stuff)([^"]+)"[^>]*><img[^>]+>[^>]+>[^>]+>[^>]+>([^<]+)',
                  [roIgnoreCase]);
                if m.Success then
                begin
                  p.Clear;
                  p.name := m.Groups.Item[3].Value;
                  TThread.Synchronize(nil,
                    procedure()
                    begin
                      p.itype := TDLItemType(config.ReadInteger(INI_PLUGINS, p.name,
                        Integer(itPlugin)));
                    end);
                  if m.Groups.Item[1].Value.Equals('download') then
                  try
                    if m.Groups.Item[2].Value.Contains('xmp-asio') or m.Groups.Item[2].Value.Contains
                      ('xmp-ds') or m.Groups.Item[2].Value.Contains('xmp-lha') then
                      Continue;
                    p.url := 'https://www.un4seen.com/download' + m.Groups.Item[2].Value;
                    xmhttp.Head(p.url);
                  finally
                    for h := 0 to Pred(xmhttp.Response.RawHeaders.Count) do
                    begin
                      z := TRegEx.Match(xmhttp.Response.RawHeaders[h],
                        '^Refresh:\s*(\d+)[^\=]+\=(.*)$');
                      if z.Success then
                      begin
                        p.url := 'https://www.un4seen.com' + z.Groups.Item[2].Value;
                        try
                          output.Clear;
                          xmhttp.Get(p.url, output);
                          output.SaveToFile(TPath.GetFileName(p.url));
                          if TZipFile.IsValid(TPath.GetFileName(p.url)) then
                          begin
                            if TPath.GetFileNameWithoutExtension(p.url).Equals(xmpzip)
                              then
                              TZipFile.ExtractZipFile(TPath.GetFileName(p.url), '')
                            else
                              TZipFile.ExtractZipFile(TPath.GetFileName(p.url), SubDir +
                                TPath.GetFileNameWithoutExtension(p.url));
                            DeleteFile(TPath.GetFileName(p.url));
                          end;
                        finally
                          p.size := xmhttp.Response.ContentLength;
                          p.date := xmhttp.Response.LastModified;
                        end;
                        Break;
                      end;
                    end;
                  end
                  else if m.Groups.Item[1].Value.Equals('stuff') then
                  try
                    p.url := 'https://www.un4seen.com/stuff' + m.Groups.Item[2].Value;
                    output.Clear;
                    xmhttp.Get(p.url, output);
                    output.SaveToFile(TPath.GetFileName(p.url));
                      //TFile.SetLastAccessTime(TPath.GetFileName(p.url), xmhttp.Response.LastModified);

                      //TFile.SetLastWriteTime(TPath.GetFileName(p.url), xmhttp.Response.LastModified);

                      //TFile.SetCreationTime(TPath.GetFileName(p.url), xmhttp.Response.LastModified);
                    if TZipFile.IsValid(TPath.GetFileName(p.url)) then
                    begin
                      TZipFile.ExtractZipFile(TPath.GetFileName(p.url), SubDir + TPath.GetFileNameWithoutExtension
                        (p.url));
                      DeleteFile(TPath.GetFileName(p.url));
                    end
                    else if not TPath.GetFileName(p.url).Equals('xmplay.exe') then
                    begin
                      ForceDirectories(SubDir + TPath.GetFileNameWithoutExtension(p.url) +
                        '\');
                      if TFile.Exists(SubDir + TPath.GetFileNameWithoutExtension(p.url) +
                        '\' + TPath.GetFileName(p.url)) then
                        TFile.Delete(SubDir + TPath.GetFileNameWithoutExtension(p.url) +
                          '\' + TPath.GetFileName(p.url));
                      TFile.Move(TPath.GetFileName(p.url), SubDir + TPath.GetFileNameWithoutExtension
                        (p.url) + '\' + TPath.GetFileName(p.url))
                    end;
                  finally
                    p.size := xmhttp.Response.ContentLength;
                    p.date := xmhttp.Response.LastModified;
                  end
                  else if m.Groups.Item[1].Value.Equals('forum') then
                  try
                    z := TRegEx.Match(m.Groups.Item[2].Value, 'topic=(\d+)');
                    if z.Success then
                      if not UrlByForumId(z.Groups.Item[1].Value.ToInteger).IsEmpty then
                      begin
                        xmhttp.HandleRedirects := True;
                        xmhttp.Request.UserAgent := USER_AGENT;
                        try
                          buffer := xmhttp.Get(UrlByForumId(z.Groups.Item[1].Value.ToInteger)
                            + '/releases/latest');
                        finally
                          q := TRegEx.Match(buffer, '\/releases\/download\/([^"]+)');
                          if q.Success then
                          try
                            p.url := UrlByForumId(z.Groups.Item[1].Value.ToInteger) + q.Groups.Item
                              [0].Value;
                            TThread.Synchronize(nil,
                              procedure()
                              begin
                                //fMain.Caption := (p.url);
                              end);
                            output.Clear;
                            xmhttp.Get(p.url, output);
                            output.SaveToFile(TPath.GetFileName(p.url));
                            if TZipFile.IsValid(TPath.GetFileName(p.url)) then
                            begin
                              TZipFile.ExtractZipFile(TPath.GetFileName(p.url), SubDir +
                                TPath.GetFileNameWithoutExtension(p.url));
                              DeleteFile(TPath.GetFileName(p.url));
                            end;
                          finally
                            p.size := xmhttp.Response.ContentLength;
                            p.date := xmhttp.Response.LastModified;
                          end;
                        end;
                        //xmhttp.OnHeadersAvailable := nil;
                        xmhttp.HandleRedirects := False;
                            //Text := buffer;
                            //SaveToFile('D:\RADStudio\Projects\XMUPD\Win32\Debug\1.htm');
                            //ExitProcess(0);
                      end
                      else
                        p.url := 'https://www.un4seen.com/forum' + m.Groups.Item[2].Value;
                  finally

                  end;
                  plugins.Add(p);
                  TThread.Synchronize(nil,
                    procedure()
                    begin
                      fMain.lbPlugins.Items.Add(p.name);
                    end);
                  {else
                  begin
                    p.url := m.Groups.Item[1].Value + m.Groups.Item[2].Value;
                  end;}
                end;
              end;
          end;
        //SaveToFile('1.htm');
      finally
        Free;
        FreeAndNil(xmhttp);
        FreeAndNil(xmssl);
        FreeAndNil(output);
      end;
      plugins.Sort(TComparer<TDLItem>.Construct(
        function(const Left, Right: TDLItem): Integer
        begin
          Result := CompareStr(Left.name, Right.name);
        end));
      TThread.Synchronize(nil,
        procedure()
        var
          p: TDLItem;
        begin
          fMain.lbPlugins.Clear;
          for p in plugins do
            fMain.lbPlugins.Items.Add(p.name);
          MessageBeep(MB_ICONINFORMATION);
          MessageBox(Handle, 'Updated', 'Finish', MB_ICONINFORMATION);
        end);
    end).Start;
end;

{ TIniFile }

function TIniFile.ReadInteger(const Section, Ident: string; Default: Integer): Integer;
begin
  if not ValueExists(Section, Ident) then
    WriteInteger(Section, Ident, Default);
  Result := inherited ReadInteger(Section, Ident, Default);
end;

procedure TfMain.lbPluginsClick(Sender: TObject);
begin
  ShowMessage(DateTimeToStr(plugins[lbPlugins.ItemIndex].Date) + ' ' + plugins[lbPlugins.ItemIndex].SIZE.ToString);
end;

procedure TfMain.HeaderOnly(Sender: TObject; AHeaders: TIdHeaderList; var VContinue:
  Boolean);
begin
  VContinue := False;
end;

{ TDLItem }

procedure TDLItem.Clear;
begin
  url := EmptyStr;
  Name := EmptyStr;
  itype := itUnknown;
  SIZE := 0;
  Date := TDateTime(0);
end;

initialization
  // ShowMessage(DateToStr(HIWBase.IdGlobalProtocols.RawStrInternetToDateTime('Mon, 29 Apr 2019 13:21:47 GMT')));
 // ExitProcess(0);
  plugins := TDLItems.Create;
  config := TIniFile.Create(System.IOUtils.TPath.ChangeExtension(ParamStr(0), 'ini'));

finalization
  FreeAndNil(plugins);
  FreeAndNil(config);

end.

