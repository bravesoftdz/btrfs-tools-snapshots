unit datamodule;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, process, ExtParams, IniFiles, cverinfo;

type

  { Tdm }

  Tdm = class(TDataModule)
    params: TExtParams;
    proc: TProcess;
    procedure DataModuleCreate(Sender: TObject);
    procedure DataModuleDestroy(Sender: TObject);
  private
    ss: TStringList;
    function sciezka_wstecz(sciezka: string): string;
    function sciezka_nazwa_katalogu(sciezka: string): string;
    function sciezka_normalizacja(sciezka: string): string;
    procedure reboot;
    function spakuj(katalog: string): integer;
    function rozpakuj(katalog: string): integer;
    function wyczysc_zasob(katalog: string): integer;
    function nowy_wolumin(nazwa: string): integer;
    function usun_archiwum(katalog: string): integer;
  public
    ini: TIniFile;
    smount,sfstab: TStringList;
    function init: boolean;
    function wersja: string;
    procedure zamontuj(device,mnt,subvol: string; force: boolean = false);
    procedure odmontuj(mnt: string; force: boolean = false);
    function migawki(nazwa: string): TStringList;
    function subvolume_to_strdatetime(nazwa: string): string;
    function get_default: integer;
    procedure get_default(var id: integer; var nazwa: string; var migawka: boolean);
    procedure set_default(id: integer);
    function whoami: string;
    function list_all: TStringList;
    function list(subvolume: string = ''): boolean;
    function wczytaj_woluminy: TStringList;
    procedure nowa_migawka(force: boolean = false);
    procedure nowa_migawka(zrodlo,cel: string);
    procedure usun_migawke(nazwa: string; force: boolean = false);
    procedure convert_partition(sciezka,nazwa_woluminu: string);
    function generuj_grub_menuitem: TStringList;
    function update_grub: integer;
    procedure generuj_btrfs_grub_migawki;
  end;

var
  dm: Tdm;

implementation

uses
  ecode, config, BaseUnix, Unix;

{$R *.lfm}

{ Tdm }

procedure Tdm.DataModuleCreate(Sender: TObject);
begin
  ss:=TStringList.Create;
  smount:=TStringList.Create;
  sfstab:=TStringList.Create;
  ini:=TIniFile.Create(_CONF);
end;

procedure Tdm.DataModuleDestroy(Sender: TObject);
begin
  ss.Free;
  smount.Free;
  sfstab.Free;
end;

function Tdm.sciezka_wstecz(sciezka: string): string;
var
  s: string;
  i,l: integer;
begin
  s:=sciezka;
  l:=length(s);
  if s[l]='/' then delete(s,l,1);
  for i:=length(sciezka) downto 1 do
  begin
    l:=length(s);
    if s[l]='/' then
    begin
      delete(s,l,1);
      break;
    end else delete(s,l,1);
  end;
  if s='' then s:='/';
  result:=s;
end;

function Tdm.sciezka_nazwa_katalogu(sciezka: string): string;
var
  s: string;
  l,a: integer;
begin
  s:=sciezka;
  l:=length(s);
  if s[l]='/' then delete(s,l,1);
  while true do
  begin
    a:=pos('/',s);
    if a=0 then break else delete(s,1,a);
  end;
  result:=s;
end;

function Tdm.sciezka_normalizacja(sciezka: string): string;
var
  s: string;
begin
  s:=sciezka;
  while pos('//',s)>0 do s:=StringReplace(s,'//','/',[]);
  result:=s;
end;

procedure Tdm.reboot;
begin
  ss.Clear;
  proc.Options:=[];
  proc.Parameters.Clear;
  proc.Executable:='shutdown';
  proc.Parameters.Add('-r');
  proc.Parameters.Add('now');
  proc.Execute;
  proc.Terminate(0);
end;

function Tdm.spakuj(katalog: string): integer;
var
  pom,workdir,nazwa,plik: string;
begin
  pom:=sciezka_normalizacja(_MNT+'/'+_ROOT+'/'+katalog);
  workdir:=sciezka_wstecz(pom);
  nazwa:=sciezka_nazwa_katalogu(pom);
  plik:=nazwa+'.tgz';
  ss.Clear;
  proc.Parameters.Clear;
  proc.Executable:='tar';
  proc.Parameters.Add('cvzf');
  proc.Parameters.Add(plik);
  proc.Parameters.Add(nazwa);
  proc.CurrentDirectory:=workdir;
  proc.Execute;
  result:=proc.ExitCode;
  proc.Terminate(0);
end;

function Tdm.rozpakuj(katalog: string): integer;
var
  pom,workdir,nazwa,plik: string;
begin
  pom:=sciezka_normalizacja(_MNT+'/'+_ROOT+'/'+katalog);
  workdir:=sciezka_wstecz(pom);
  nazwa:=sciezka_nazwa_katalogu(pom);
  plik:=nazwa+'.tgz';
  ss.Clear;
  proc.Parameters.Clear;
  proc.CurrentDirectory:=workdir;
  proc.Executable:='tar';
  proc.Parameters.Add('xvzf');
  proc.Parameters.Add(plik);
  proc.Execute;
  result:=proc.ExitCode;
  proc.Terminate(0);
end;

function Tdm.wyczysc_zasob(katalog: string): integer;
var
  pom,workdir,nazwa: string;
begin
  pom:=sciezka_normalizacja(_MNT+'/'+_ROOT+'/'+katalog);
  workdir:=sciezka_wstecz(pom);
  nazwa:=sciezka_nazwa_katalogu(pom);
  ss.Clear;
  proc.Parameters.Clear;
  proc.CurrentDirectory:=workdir;
  proc.Executable:='rm';
  proc.Parameters.Add('-f');
  proc.Parameters.Add('-R');
  proc.Parameters.Add(nazwa);
  proc.Execute;
  mkdir(workdir+'/'+nazwa);
  result:=proc.ExitCode;
  proc.Terminate(0);
end;

function Tdm.nowy_wolumin(nazwa: string): integer;
begin
  ss.Clear;
  proc.Parameters.Clear;
  proc.CurrentDirectory:=_MNT;
  proc.Executable:='btrfs';
  proc.Parameters.Add('subvolume');
  proc.Parameters.Add('create');
  proc.Parameters.Add(nazwa);
  proc.Execute;
  result:=proc.ExitCode;
  proc.Terminate(0);
end;

function Tdm.usun_archiwum(katalog: string): integer;
var
  pom,workdir,nazwa,plik: string;
begin
  pom:=sciezka_normalizacja(_MNT+'/'+_ROOT+'/'+katalog);
  workdir:=sciezka_wstecz(pom);
  nazwa:=sciezka_nazwa_katalogu(pom);
  plik:=nazwa+'.tgz';
  ss.Clear;
  proc.Parameters.Clear;
  proc.CurrentDirectory:=workdir;
  proc.Executable:='rm';
  proc.Parameters.Add('-f');
  proc.Parameters.Add(plik);
  proc.Execute;
  result:=proc.ExitCode;
  proc.Terminate(0);
end;

function Tdm.init: boolean;
var
  i: integer;
  s: string;
begin
  if _DEBUG then exit;
  (* DEVICE *)
  smount.Clear;
  proc.Parameters.Clear;
  proc.Executable:='mount';
  proc.Execute;
  smount.LoadFromStream(proc.Output);
  proc.Terminate(0);
  for i:=smount.Count-1 downto 0 do if pos('/dev/sd',smount[i])=0 then smount.Delete(i);
  if dm.params.IsParam('device') then _DEVICE:=dm.params.GetValue('device') else for i:=0 to smount.Count-1 do
  begin
    s:=smount[i];
    if pos('on / type',s)>0 then
    begin
      _DEVICE:=GetLineToStr(s,1,' ');
      break;
    end;
  end;
  if _DEVICE='' then
  begin
    writeln('UWAGA! NIEZNANE URZĄDZENIE! WYCHODZĘ!');
    result:=false;
  end else begin
    result:=true;
  end;
  (* ROOT *)
  if dm.params.IsParam('root') then _ROOT:=dm.params.GetValue('root') else _ROOT:=dm.ini.ReadString('config','root','@');
end;

function Tdm.wersja: string;
var
  major,minor,release,build: integer;
begin
  cverinfo.GetProgramVersion(major,minor,release,build);
  result:=IntToStr(major)+'.'+IntToStr(minor)+'.'+IntToStr(release)+'-'+IntToStr(build);
end;

procedure Tdm.zamontuj(device, mnt, subvol: string; force: boolean);
begin
  if _MONTOWANIE_RECZNE and (not force) then exit;
  inc(_MNT_COUNT);
  if (_MNT_COUNT>1) and (not force) then exit;
  proc.Parameters.Clear;
  proc.Executable:='mount';
  proc.Parameters.Add('-o');
  proc.Parameters.Add('subvol='+subvol);
  proc.Parameters.Add(device);
  proc.Parameters.Add(mnt);
  proc.Execute;
  proc.Terminate(0);
end;

procedure Tdm.odmontuj(mnt: string; force: boolean);
begin
  if _MONTOWANIE_RECZNE and (not force) then exit;
  dec(_MNT_COUNT);
  if (_MNT_COUNT>0) and (not force) then exit;
  proc.Parameters.Clear;
  proc.Executable:='umount';
  proc.Parameters.Add(mnt);
  proc.Execute;
  proc.Terminate(0);
  if force then _MNT_COUNT:=0;
end;

function Tdm.migawki(nazwa: string): TStringList;
var
  s,pom: string;
  i,a: integer;
begin
  zamontuj(_DEVICE,_MNT,'/');
  proc.CurrentDirectory:=_MNT;
  proc.Parameters.Clear;
  proc.Executable:='btrfs';
  proc.Parameters.Add('subvolume');
  proc.Parameters.Add('show');
  proc.Parameters.Add(nazwa);
  proc.Execute;
  ss.LoadFromStream(proc.Output);
  proc.Terminate(0);
  proc.CurrentDirectory:='';
  odmontuj(_MNT);
  for i:=0 to ss.Count-1 do
  begin
    s:=ss[i];
    a:=pos('Snapshot(s):',s);
    if a>0 then
    begin
      a:=i+1;
      break;
    end;
  end;
  s:='';
  for i:=a to ss.Count-1 do s:=s+ss[i]+' ';
  s:=trim(StringReplace(s,#9,'',[rfReplaceAll]));
  s:=StringReplace(s,' ',';',[rfReplaceAll]);
  ss.Clear;
  i:=0;
  while true do
  begin
    inc(i);
    pom:=GetLineToStr(s,i,';');
    if pom='' then break;
    ss.Add(pom);
  end;
  result:=ss;
end;

function Tdm.subvolume_to_strdatetime(nazwa: string): string;
var
  s,pom: string;
  i,a: integer;
  FS: TFormatSettings;
begin
  FS.ShortDateFormat:='y/m/d';
  FS.DateSeparator:='-';
  pom:='';
  zamontuj(_DEVICE,_MNT,'/');
  proc.CurrentDirectory:=_MNT;
  proc.Parameters.Clear;
  proc.Executable:='btrfs';
  proc.Parameters.Add('subvolume');
  proc.Parameters.Add('show');
  proc.Parameters.Add(nazwa);
  proc.Execute;
  ss.LoadFromStream(proc.Output);
  proc.Terminate(0);
  proc.CurrentDirectory:='';
  odmontuj(_MNT);
  for i:=0 to ss.Count-1 do
  begin
    s:=ss[i];
    a:=pos('Creation time:',s);
    if a>0 then break;
  end;
  delete(s,1,a+14);
  s:=trim(StringReplace(s,#9,'',[rfReplaceAll]));
  result:=s;
end;

function Tdm.get_default: integer;
begin
  ss.Clear;
  proc.Parameters.Clear;
  proc.Executable:='btrfs';
  proc.Parameters.Add('subvolume');
  proc.Parameters.Add('get-default');
  proc.Parameters.Add('/');
  proc.Execute;
  ss.LoadFromStream(proc.Output);
  proc.Terminate(0);
  result:=StrToInt(GetLineToStr(ss[0],2,' '));
end;

procedure Tdm.get_default(var id: integer; var nazwa: string;
  var migawka: boolean);
begin
  ss.Clear;
  proc.Parameters.Clear;
  proc.Executable:='btrfs';
  proc.Parameters.Add('subvolume');
  proc.Parameters.Add('get-default');
  proc.Parameters.Add('/');
  proc.Execute;
  ss.LoadFromStream(proc.Output);
  proc.Terminate(0);
  id:=StrToInt(GetLineToStr(ss[0],2,' '));
  nazwa:=GetLineToStr(ss[0],9,' ');
  migawka:=pos('migawka',nazwa)>0;
end;

procedure Tdm.set_default(id: integer);
var
  i: integer;
begin
  ss.Clear;
  proc.CurrentDirectory:=_MNT;
  proc.Parameters.Clear;
  proc.Executable:='btrfs';
  proc.Parameters.Add('subvolume');
  proc.Parameters.Add('set-default');
  proc.Parameters.Add(IntToStr(id));
  proc.Parameters.Add('/');
  proc.Execute;
  ss.LoadFromStream(proc.Output);
  proc.Terminate(0);
  for i:=0 to ss.Count-1 do writeln(ss[i]);
end;

function Tdm.whoami: string;
begin
  ss.Clear;
  proc.Parameters.Clear;
  proc.Executable:='whoami';
  proc.Execute;
  ss.LoadFromStream(proc.Output);
  proc.Terminate(0);
  result:=ss[0];
end;

function Tdm.list_all: TStringList;
begin
  zamontuj(_DEVICE,_MNT,'/');
  proc.CurrentDirectory:=_MNT;
  proc.Parameters.Clear;
  proc.Executable:='btrfs';
  proc.Parameters.Add('subvolume');
  proc.Parameters.Add('list');
  proc.Parameters.Add('.');
  proc.Execute;
  ss.LoadFromStream(proc.Output);
  proc.Terminate(0);
  proc.CurrentDirectory:='';
  odmontuj(_MNT);
  result:=ss;
end;

function Tdm.list(subvolume: string): boolean;
var
  i,id: integer;
  s,nn,nazwa,sdata: string;
  istnieje: boolean;
begin
  list_all;
  for i:=0 to ss.Count-1 do
  begin
    s:=ss[i];
    id:=StrToInt(GetLineToStr(s,2,' '));
    nn:=GetLineToStr(s,9,' ');
    if subvolume='' then
    begin
      nazwa:=GetLineToStr(nn,1,'_');
      sdata:=GetLineToStr(nn,2,'_');
      if nazwa='@migawka' then writeln('Migawka:  ID: ',id,', NAME: ',nazwa,'_',sdata,', DATE: ',sdata)
                          else writeln('Wolumin:  ID: ',id,', NAME: ',nn);
    end else begin
      if nn=subvolume then
      begin
        istnieje:=true;
        break;
      end;
    end;
  end;
  if subvolume='' then result:=true else result:=istnieje;
end;

function Tdm.wczytaj_woluminy: TStringList;
var
  id,i,j,a: integer;
  s,pom: string;
  tab,tab1,tab2: TStringList;
  sciezka,wolumin: string;
  s1: string;
  vol: TStringList;
begin
  id:=dm.get_default;
  s:='ID '+IntToStr(id)+' gen';

  vol:=TStringList.Create;
  try
    tab:=TStringList.Create;
    tab1:=TStringList.Create;
    tab2:=TStringList.Create;
    try
      tab.Assign(dm.list_all);
      for i:=0 to tab.Count-1 do tab1.Add(GetLineToStr(tab[i],9,' '));

      i:=0;
      while true do
      begin
        if i>tab1.Count-1 then break;
        sciezka:=tab1[i];
        tab2.Assign(dm.migawki(sciezka));
        wolumin:=tab1[i];
        for j:=0 to tab2.Count-1 do
        begin
          s1:=tab2[j];
          a:=StringToItemIndex(tab1,s1);
          if a>-1 then
          begin
            pom:=tab[a];
            tab.Delete(a);
            tab.Insert(i+1,'   \> '+pom);
            pom:=tab1[a];
            tab1.Delete(a);
            tab1.Insert(i+1,pom);
            inc(i);
          end;
        end;
        inc(i);
      end;

      vol.Assign(tab);
    finally
      tab.Free;
      tab1.Free;
      tab2.Free;
    end;

    for i:=0 to vol.Count-1 do
    begin
      pom:=vol[i];
      if pos(s,pom)>0 then
      begin
        vol.Delete(i);
        vol.Insert(i,pom+' [ *** Auto-Start *** ]');
        break;
      end;
    end;
    ss.Assign(vol);
  finally
    vol.Free;
  end;
  result:=ss;
end;

procedure Tdm.nowa_migawka(force: boolean);
var
  migawka: string;
begin
  zamontuj(_DEVICE,_MNT,'/');
  migawka:='@'+_ROOT+'_'+FormatDateTime('yyyy-mm-dd',date);
  if dm.list(migawka) then dm.usun_migawke(migawka);
  proc.Parameters.Clear;
  proc.CurrentDirectory:=_MNT;
  proc.Executable:='btrfs';
  proc.Parameters.Add('subvolume');
  proc.Parameters.Add('snapshot');
  proc.Parameters.Add(_ROOT);
  proc.Parameters.Add(migawka);
  proc.Execute;
  proc.Terminate(0);
  proc.CurrentDirectory:='';
  odmontuj(_MNT);
end;

procedure Tdm.nowa_migawka(zrodlo, cel: string);
begin
  zamontuj(_DEVICE,_MNT,'/');
  proc.Parameters.Clear;
  proc.CurrentDirectory:=_MNT;
  proc.Executable:='btrfs';
  proc.Parameters.Add('subvolume');
  proc.Parameters.Add('snapshot');
  proc.Parameters.Add(zrodlo);
  proc.Parameters.Add(cel);
  proc.Execute;
  proc.Terminate(0);
  proc.CurrentDirectory:='';
  odmontuj(_MNT);
end;

procedure Tdm.usun_migawke(nazwa: string; force: boolean);
begin
  if (not force) and (pos('@@',nazwa)=0) then
  begin
    writeln('Próbujesz usunąć wolumin, tego typu operacje zostały zablokowane!');
    writeln('By usunąć wolumin musisz użyć flagi [--force].');
    exit;
  end;
  zamontuj(_DEVICE,_MNT,'/');
  proc.Parameters.Clear;
  proc.CurrentDirectory:=_MNT;
  proc.Executable:='btrfs';
  proc.Parameters.Add('subvolume');
  proc.Parameters.Add('delete');
  proc.Parameters.Add(nazwa);
  proc.Execute;
  proc.Terminate(0);
  proc.CurrentDirectory:='';
  odmontuj(_MNT);
end;

procedure Tdm.convert_partition(sciezka, nazwa_woluminu: string);
var
  subvolume: string;
  exitcode: integer;
begin
  (* określenie nazwy woluminu *)
  subvolume:='';
  if nazwa_woluminu<>'' then subvolume:=nazwa_woluminu
  else if sciezka='/home' then subvolume:='@home'
  else if sciezka='/var' then subvolume:='@var'
  else if sciezka='/var/cache' then subvolume:='@cache';
  if subvolume='' then
  begin
    writeln('*** Operacja przerwana! ***');
    writeln('Podana ścieżka nie została zdefiniowana w programie i brakuje odpowiedniej nazwy woluminu.');
    writeln('Proszę o dodatkowe zdefiniowanie nazwy woluminu za pomocą parametru "--subvolume".');
    exit;
  end;
  (* wykonuję procedurę przekonwertowania katalogu *)
  writeln('Montuję zasób główny...');
  zamontuj(_DEVICE,_MNT,'/');
  try
    writeln('Pakuję zawartość zasobu...');
    exitcode:=spakuj(sciezka);
    if exitcode<>0 then
    begin
      writeln('Wystąpił błąd nr ',exitcode,', przerywam...');
      exit;
    end;
    writeln('Usuwam zawartość zasobu...');
    exitcode:=wyczysc_zasob(sciezka);
    if exitcode<>0 then
    begin
      writeln('Wystąpił błąd nr ',exitcode,', przerywam...');
      exit;
    end;
    writeln('Tworzę nowy wolumin...');
    exitcode:=nowy_wolumin(subvolume);
    if exitcode<>0 then
    begin
      writeln('Wystąpił błąd nr ',exitcode,', przerywam...');
      exit;
    end;
    writeln('Odtwarzam zawartość woluminu...');
    try
      zamontuj(_DEVICE,sciezka_normalizacja(_MNT+'/'+_ROOT+'/'+sciezka),subvolume);
      exitcode:=rozpakuj(sciezka);
      if exitcode<>0 then
      begin
        writeln('Wystąpił błąd nr ',exitcode,', przerywam...');
        exit;
      end;
    finally
      odmontuj(sciezka_normalizacja(_MNT+'/'+_ROOT+'/'+sciezka));
    end;
    writeln('Usuwam spakowaną zawartość zasobu, która jest już nie potrzebna...');
    usun_archiwum(sciezka);
  finally
    writeln('Odmontowuję zasób główny...');
    odmontuj(_MNT);
  end;
end;

function Tdm.generuj_grub_menuitem: TStringList;
var
  b: boolean;
  i,j,a: integer;
  s: string;
begin
  ss.Clear;
  ss.LoadFromFile('/boot/grub/grub.cfg');
  for i:=0 to ss.Count-1 do
  begin
    a:=pos('menuentry ',ss[0]);
    if a>0 then break;
    ss.Delete(0);
  end;
  b:=false;
  for i:=0 to ss.Count-1 do
  begin
    if b then ss.Delete(j+1) else
    begin
      j:=i;
      a:=pos('}',ss[j]);
    end;
    if a>0 then b:=true;
  end;
  s:=ss[0];
  a:=pos(''' ',s);
  insert(' ($MIGAWKA$)',s,a);
  ss.Delete(0);
  ss.Insert(0,s);
  result:=ss;
end;

function Tdm.update_grub: integer;
begin
  ss.Clear;
  proc.Parameters.Clear;
  proc.Executable:='update-grub';
  proc.Execute;
  result:=proc.ExitCode;
  proc.Terminate(0);
end;

procedure Tdm.generuj_btrfs_grub_migawki;
var
  wzor,s,sciezka,nazwa,dzien: string;
  i: integer;
  err: integer;
  vol: TStringList;
begin
  vol:=TStringList.Create;
  try
    vol.Assign(dm.wczytaj_woluminy);
    wzor:=dm.generuj_grub_menuitem.Text;
    ss.Clear;
    for i:=0 to vol.Count-1 do
    begin
      s:=vol[i];
      if s[1]='I' then sciezka:=GetLineToStr(s,9,' ') else
      begin
        if sciezka='@' then
        begin
          s:=StringReplace(s,'   \> ','',[]);
          nazwa:=GetLineToStr(s,9,' ');
          dzien:=GetLineToStr(nazwa,2,'_');
          ss.Add(StringReplace(StringReplace(wzor,'@',nazwa,[rfReplaceAll]),'$MIGAWKA$','Migawka z dnia: '+dzien,[]));
        end;
      end;
    end;
    ss.Insert(0,'#!/bin/sh');
    ss.Insert(1,'exec tail -n +3 $0');
    ss.Insert(2,'');
    ss.SaveToFile('/etc/grub.d/10_linux_btrfs');
    fpChmod('/etc/grub.d/10_linux_btrfs',&755);
    err:=update_grub;
    if err<>0 then writeln('Błąd podczas wykonania polecenia "update-grub" nr '+IntToStr(err));
  finally
    vol.Free;
  end;
end;

end.

