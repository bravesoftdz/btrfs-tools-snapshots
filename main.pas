unit main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Buttons;

type

  { TFMain }

  TFMain = class(TForm)
    BitBtn1: TBitBtn;
    BitBtn2: TBitBtn;
    BitBtn3: TBitBtn;
    lMount: TListBox;
    procedure BitBtn1Click(Sender: TObject);
    procedure BitBtn2Click(Sender: TObject);
    procedure BitBtn3Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure lMountClick(Sender: TObject);
  private
    lMountSciezki: TStringList;
    procedure init;
    procedure wczytaj_woluminy;
    procedure refresh_przyciski;
    procedure generuj_btrfs_grub_migawki;
  public

  end;

var
  FMain: TFMain;

implementation

uses
  config, datamodule, ecode, BaseUnix, Unix;

{$R *.lfm}

{ TFMain }

procedure TFMain.FormCreate(Sender: TObject);
begin
  lMountSciezki:=TStringList.Create;
  Init;
end;

procedure TFMain.BitBtn1Click(Sender: TObject);
var
  s: string;
  id: integer;
  nazwa,migawka: string;
begin
  s:=lMount.Items[lMount.ItemIndex];
  s:=StringReplace(s,'   \> ','',[]);
  id:=StrToInt(GetLineToStr(s,2,' '));
  nazwa:=GetLineToStr(s,9,' ');
  migawka:='@'+nazwa+'_'+FormatDateTime('yyyy-mm-dd',date);
  if dm.list(migawka) then
  begin
    dm.usun_migawke(migawka);
    wczytaj_woluminy;
    application.ProcessMessages;
    sleep(500);
  end;
  dm.nowa_migawka(nazwa,migawka);
  wczytaj_woluminy;
  if nazwa='@' then generuj_btrfs_grub_migawki;
end;

procedure TFMain.BitBtn2Click(Sender: TObject);
var
  s: string;
  id: integer;
  nazwa: string;
begin
  s:=lMount.Items[lMount.ItemIndex];
  s:=StringReplace(s,'   \> ','',[]);
  id:=StrToInt(GetLineToStr(s,2,' '));
  nazwa:=GetLineToStr(s,9,' ');
  dm.usun_migawke(nazwa);
  wczytaj_woluminy;
  if pos('@@_',nazwa)=1 then generuj_btrfs_grub_migawki;
end;

procedure TFMain.BitBtn3Click(Sender: TObject);
begin
  generuj_btrfs_grub_migawki;
end;

procedure TFMain.FormDestroy(Sender: TObject);
begin
  lMountSciezki.Free;
end;

procedure TFMain.lMountClick(Sender: TObject);
begin
  refresh_przyciski;
end;

procedure TFMain.init;
begin
  wczytaj_woluminy;
end;

procedure TFMain.wczytaj_woluminy;
begin
  lMount.Items.Assign(dm.wczytaj_woluminy);
  lMount.ItemIndex:=0;
  refresh_przyciski;
end;

procedure TFMain.refresh_przyciski;
var
  s: string;
  migawka: boolean;
begin
  s:=lMount.Items[lMount.ItemIndex];
  migawka:=pos('   \> ',s)>0;
  BitBtn1.Enabled:=not migawka;
  BitBtn2.Enabled:=migawka;
end;

procedure TFMain.generuj_btrfs_grub_migawki;
var
  wzor,s,sciezka,nazwa,dzien: string;
  i: integer;
  ss: TStringList;
  err: integer;
begin
  wzor:=dm.generuj_grub_menuitem.Text;
  ss:=TStringList.Create;
  try
    for i:=0 to lMount.Items.Count-1 do
    begin
      s:=lMount.Items[i];
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
    err:=dm.update_grub;
    if err<>0 then showmessage('Błąd podczas wykonania polecenia "update-grub" nr '+IntToStr(err)+'.');
  finally
    ss.Free;
  end;
end;

end.

