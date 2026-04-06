unit Sprite;

interface

uses VGA, GenTypes, PCX, MiniXML, StrUtil;

const SpritePlayType_Forward = 0;
const SpritePlayType_PingPong = 1;
const SpritePlayType_Once = 2;

const MaxSpriteFrames = 64;

type
  PSpriteFrame = ^TSpriteFrame;
  TSpriteFrame = record
    Rect: TRectangle;    { Source rect in spritesheet }
    OffsetX: Integer;     { Drawing offset X (default 0) }
    OffsetY: Integer;     { Drawing offset Y (default 0) }
    Duration: Real;       { Per-frame duration in seconds; 0 = use uniform }
  end;

type
  PSprite = ^TSprite;
  TSprite = record
  	Image: PImage;
  	Frames: array[0..MaxSpriteFrames - 1] of TSpriteFrame;
  	FrameCount: Byte;
  	Width: Word;
  	Height: Word;
  	Duration: Real; { Seconds - total for uniform timing }
  	PlayType: Byte;
  	HasFrameDurations: Boolean; { True if per-frame durations are set }
  	TotalDuration: Real;        { Sum of frame durations (variable mode) }
  end;

type
  PSpriteInstance = ^TSpriteInstance;
  TSpriteInstance = record
  	Sprite: PSprite;
  	Hidden: Boolean;
  	X: Integer;
  	Y: Integer;
  	FlipX: Boolean;
  	FlipY: Boolean;
  	CurrentTime: Real; { Seconds }
  	PlayBackward: Boolean; { Only matters when PlayMode is PingPong }
  end;

const MaxSPXSprites = 32;

type
  PSpriteSheet = ^TSpriteSheet;
  TSpriteSheet = record
    Image: TImage;
    Palette: TPalette;
    Sprites: array[0..MaxSPXSprites - 1] of TSprite;
    Names: array[0..MaxSPXSprites - 1] of String[20];
    Count: Byte;
  end;

function LoadSPX(const Filename: String; var Sheet: TSpriteSheet): Boolean;
function GetSPXSprite(var Sheet: TSpriteSheet; const Name: String): PSprite;
procedure FreeSPX(var Sheet: TSpriteSheet);
function GetLoadSPXError: String;

procedure UpdateSprite(var SpriteInstance: TSpriteInstance; DeltaTime: Real);
procedure DrawSprite(var SpriteInstance: TSpriteInstance; FrameBuffer: PFrameBuffer);
function SpriteGetCurrentFrame(var SpriteInstance: TSpriteInstance): Byte;
function CheckSpriteCollision(SpriteA, SpriteB: PSpriteInstance): Boolean;

implementation

function SpriteGetCurrentFrame(var SpriteInstance: TSpriteInstance): Byte;
var
  Progress: Real;
  Accum: Real;
  FrameNumber: Byte;
  I: Byte;
  FC: Byte;
  DefaultDur: Real;
begin
  FC := SpriteInstance.Sprite^.FrameCount;

  { Handle stopped animation (PlayType_Once finished) }
  if SpriteInstance.CurrentTime < 0.0 then
  begin
    FrameNumber := FC - 1;
  end
  else if SpriteInstance.Sprite^.HasFrameDurations then
  begin
    { Variable frame durations - cumulative lookup }
    DefaultDur := SpriteInstance.Sprite^.Duration / FC;
    Accum := 0.0;
    FrameNumber := FC - 1;
    for I := 0 to FC - 1 do
    begin
      if SpriteInstance.Sprite^.Frames[I].Duration > 0.0 then
        Accum := Accum + SpriteInstance.Sprite^.Frames[I].Duration
      else
        Accum := Accum + DefaultDur;
      if Accum > SpriteInstance.CurrentTime then
      begin
        FrameNumber := I;
        Break;
      end;
    end;
    if SpriteInstance.PlayBackward then
      FrameNumber := (FC - 1) - FrameNumber;
  end
  else
  begin
    { Uniform frame durations - fast path }
    if SpriteInstance.Sprite^.Duration > 0.0 then
    begin
      Progress := (SpriteInstance.CurrentTime * FC) / SpriteInstance.Sprite^.Duration;
      if Progress >= FC then
        Progress := FC - 1;
      if Progress < 0.0 then
        Progress := 0.0;
      FrameNumber := Trunc(Progress);
      if SpriteInstance.PlayBackward then
        FrameNumber := (FC - 1) - FrameNumber;
    end
    else
      FrameNumber := 0;
  end;
  SpriteGetCurrentFrame := FrameNumber;
end;

function CheckSpriteCollision(SpriteA, SpriteB: PSpriteInstance): Boolean;
var
  FrameA, FrameB: Byte;
  RectA, RectB: TRectangle;
  ScreenAX, ScreenAY, ScreenBX, ScreenBY: Integer;
  OverlapX1, OverlapY1, OverlapX2, OverlapY2: Integer;
  X, Y: Integer;
  PixelA, PixelB: Byte;
  SrcXA, SrcYA, SrcXB, SrcYB: Integer;
  OffsetA, OffsetB: Word;
begin
  CheckSpriteCollision := False;

  { Skip if either sprite is hidden }
  if SpriteA^.Hidden or SpriteB^.Hidden then
    Exit;

  { Get current frames }
  FrameA := SpriteGetCurrentFrame(SpriteA^);
  FrameB := SpriteGetCurrentFrame(SpriteB^);
  RectA := SpriteA^.Sprite^.Frames[FrameA].Rect;
  RectB := SpriteB^.Sprite^.Frames[FrameB].Rect;

  { Calculate screen positions with offsets (mirror within bounding box when flipped) }
  if SpriteA^.FlipX then
    ScreenAX := SpriteA^.X + Integer(SpriteA^.Sprite^.Width) - Integer(RectA.Width) - SpriteA^.Sprite^.Frames[FrameA].OffsetX
  else
    ScreenAX := SpriteA^.X + SpriteA^.Sprite^.Frames[FrameA].OffsetX;
  if SpriteA^.FlipY then
    ScreenAY := SpriteA^.Y + Integer(SpriteA^.Sprite^.Height) - Integer(RectA.Height) - SpriteA^.Sprite^.Frames[FrameA].OffsetY
  else
    ScreenAY := SpriteA^.Y + SpriteA^.Sprite^.Frames[FrameA].OffsetY;
  if SpriteB^.FlipX then
    ScreenBX := SpriteB^.X + Integer(SpriteB^.Sprite^.Width) - Integer(RectB.Width) - SpriteB^.Sprite^.Frames[FrameB].OffsetX
  else
    ScreenBX := SpriteB^.X + SpriteB^.Sprite^.Frames[FrameB].OffsetX;
  if SpriteB^.FlipY then
    ScreenBY := SpriteB^.Y + Integer(SpriteB^.Sprite^.Height) - Integer(RectB.Height) - SpriteB^.Sprite^.Frames[FrameB].OffsetY
  else
    ScreenBY := SpriteB^.Y + SpriteB^.Sprite^.Frames[FrameB].OffsetY;

  { Check bounding box collision first }
  if (ScreenAX + RectA.Width <= ScreenBX) or
     (ScreenBX + RectB.Width <= ScreenAX) or
     (ScreenAY + RectA.Height <= ScreenBY) or
     (ScreenBY + RectB.Height <= ScreenAY) then
    Exit;

  { Calculate overlapping region in screen coordinates }
  if ScreenAX > ScreenBX then
    OverlapX1 := ScreenAX
  else
    OverlapX1 := ScreenBX;

  if ScreenAY > ScreenBY then
    OverlapY1 := ScreenAY
  else
    OverlapY1 := ScreenBY;

  if ScreenAX + RectA.Width < ScreenBX + RectB.Width then
    OverlapX2 := ScreenAX + RectA.Width
  else
    OverlapX2 := ScreenBX + RectB.Width;

  if ScreenAY + RectA.Height < ScreenBY + RectB.Height then
    OverlapY2 := ScreenAY + RectA.Height
  else
    OverlapY2 := ScreenBY + RectB.Height;

  { Check each pixel in the overlapping region }
  for Y := OverlapY1 to OverlapY2 - 1 do
  begin
    for X := OverlapX1 to OverlapX2 - 1 do
    begin
      { Calculate source coordinates for sprite A }
      SrcXA := X - ScreenAX;
      SrcYA := Y - ScreenAY;

      { Apply flipping for sprite A }
      if SpriteA^.FlipX then
        SrcXA := RectA.Width - 1 - SrcXA;
      if SpriteA^.FlipY then
        SrcYA := RectA.Height - 1 - SrcYA;

      { Add frame offset }
      SrcXA := SrcXA + RectA.X;
      SrcYA := SrcYA + RectA.Y;

      { Calculate source coordinates for sprite B }
      SrcXB := X - ScreenBX;
      SrcYB := Y - ScreenBY;

      { Apply flipping for sprite B }
      if SpriteB^.FlipX then
        SrcXB := RectB.Width - 1 - SrcXB;
      if SpriteB^.FlipY then
        SrcYB := RectB.Height - 1 - SrcYB;

      { Add frame offset }
      SrcXB := SrcXB + RectB.X;
      SrcYB := SrcYB + RectB.Y;

      { Get pixels from source images }
      OffsetA := SrcYA * SpriteA^.Sprite^.Image^.Width + SrcXA;
      OffsetB := SrcYB * SpriteB^.Sprite^.Image^.Width + SrcXB;
      PixelA := PByteArray(SpriteA^.Sprite^.Image^.Data)^[OffsetA];
      PixelB := PByteArray(SpriteB^.Sprite^.Image^.Data)^[OffsetB];

      { Check if both pixels are non-transparent (color 0 = transparent) }
      if (PixelA <> 0) and (PixelB <> 0) then
      begin
        CheckSpriteCollision := True;
        Exit;
      end;
    end;
  end;
end;

procedure UpdateSprite(var SpriteInstance: TSpriteInstance; DeltaTime: Real);
var
  EffDur: Real;
begin
  if SpriteInstance.CurrentTime < 0.0 then
    Exit;
  if SpriteInstance.Sprite^.HasFrameDurations then
    EffDur := SpriteInstance.Sprite^.TotalDuration
  else
    EffDur := SpriteInstance.Sprite^.Duration;
  SpriteInstance.CurrentTime := SpriteInstance.CurrentTime + DeltaTime;
  if SpriteInstance.CurrentTime > EffDur then
  begin
  	if SpriteInstance.Sprite^.PlayType = SpritePlayType_Once then
  	  SpriteInstance.CurrentTime := -1.0 { Disable update }
  	else if SpriteInstance.Sprite^.PlayType = SpritePlayType_PingPong then
  	begin
  	  SpriteInstance.PlayBackward := not SpriteInstance.PlayBackward;
  	  SpriteInstance.CurrentTime := SpriteInstance.CurrentTime - EffDur;
  	end
  	else { SpritePlayType_Forward }
  	begin
  	  SpriteInstance.CurrentTime := SpriteInstance.CurrentTime - EffDur;
  	end;
  end;
end;

procedure DrawSprite(var SpriteInstance: TSpriteInstance; FrameBuffer: PFrameBuffer);
var
  FrameNumber: Byte;
  FrameRect: TRectangle;
  DrawX, DrawY: Integer;
  OfsX, OfsY: Integer;
begin
  if SpriteInstance.Hidden then
    Exit;

  { Get current frame }
  FrameNumber := SpriteGetCurrentFrame(SpriteInstance);

  { Get the frame rectangle and offsets }
  FrameRect := SpriteInstance.Sprite^.Frames[FrameNumber].Rect;
  OfsX := SpriteInstance.Sprite^.Frames[FrameNumber].OffsetX;
  OfsY := SpriteInstance.Sprite^.Frames[FrameNumber].OffsetY;

  { Apply offsets (mirror within sprite bounding box when flipped) }
  if SpriteInstance.FlipX then
    DrawX := SpriteInstance.X + Integer(SpriteInstance.Sprite^.Width) - Integer(FrameRect.Width) - OfsX
  else
    DrawX := SpriteInstance.X + OfsX;
  if SpriteInstance.FlipY then
    DrawY := SpriteInstance.Y + Integer(SpriteInstance.Sprite^.Height) - Integer(FrameRect.Height) - OfsY
  else
    DrawY := SpriteInstance.Y + OfsY;

  { Draw the sprite frame with flipping support }
  PutFlippedImageRect(
    SpriteInstance.Sprite^.Image^,
    FrameRect,
    DrawX,
    DrawY,
    SpriteInstance.FlipX,
    SpriteInstance.FlipY,
    True,  { Transparent = True }
    FrameBuffer
  );
end;

{ SPX loading }

var
  LoadSPXError: String;

function GetLoadSPXError: String;
begin
  GetLoadSPXError := LoadSPXError;
end;

function LoadSPX(const Filename: String; var Sheet: TSpriteSheet): Boolean;
var
  Root, Child, FrameNode: PXMLNode;
  BasePath, TagName, ImgPath: String;
  I: Integer;
  SprIdx, FrameIdx: Byte;
  DefWidth, DefHeight: Word;
  HasDefSize, HasAnyFrameDur: Boolean;
  DefaultDur, TotalDur: Real;
begin
  LoadSPX := False;
  LoadSPXError := '';
  Sheet.Count := 0;
  Sheet.Image.Data := nil;

  { Extract base path }
  BasePath := '';
  for I := Length(Filename) downto 1 do
  begin
    if Filename[I] = '\' then
    begin
      BasePath := Copy(Filename, 1, I);
      Break;
    end;
  end;

  if not XMLLoadFile(Filename, Root) then
  begin
    LoadSPXError := 'Failed to parse SPX file: ' + Filename;
    Exit;
  end;

  { Find and load image }
  Child := XMLFirstChild(Root, 'image');
  if Child = nil then
  begin
    LoadSPXError := 'SPX file has no image element';
    XMLFreeTree(Root);
    Exit;
  end;

  if not XMLHasAttr(Child, 'path') then
  begin
    LoadSPXError := 'SPX image missing path attribute';
    XMLFreeTree(Root);
    Exit;
  end;

  ImgPath := BasePath + XMLAttr(Child, 'path');
  LoadPCXWithPalette(ImgPath, Sheet.Image, Sheet.Palette);
  if GetLoadPCXError <> '' then
  begin
    LoadSPXError := 'Failed to load image: ' + GetLoadPCXError;
    XMLFreeTree(Root);
    Exit;
  end;

  { Parse all sprite elements }
  SprIdx := 0;
  Child := XMLFirstChild(Root, 'sprite');
  while (Child <> nil) and (SprIdx < MaxSPXSprites) do
  begin
    if not XMLHasAttr(Child, 'name') or not XMLHasAttr(Child, 'duration') then
    begin
      LoadSPXError := 'SPX sprite missing name or duration';
      FreeSPX(Sheet);
      XMLFreeTree(Root);
      Exit;
    end;

    Sheet.Names[SprIdx] := XMLAttr(Child, 'name');
    FillChar(Sheet.Sprites[SprIdx], SizeOf(TSprite), 0);
    Sheet.Sprites[SprIdx].Image := @Sheet.Image;
    Sheet.Sprites[SprIdx].Duration := StrToReal(XMLAttr(Child, 'duration'));
    Sheet.Sprites[SprIdx].PlayType := SpritePlayType_Forward;

    { Default width/height }
    HasDefSize := XMLHasAttr(Child, 'width') and XMLHasAttr(Child, 'height');
    if HasDefSize then
    begin
      DefWidth := StrToInt(XMLAttr(Child, 'width'));
      DefHeight := StrToInt(XMLAttr(Child, 'height'));
    end
    else
    begin
      DefWidth := 0;
      DefHeight := 0;
    end;

    { Parse frames }
    FrameIdx := 0;
    HasAnyFrameDur := False;
    FrameNode := XMLFirstChild(Child, 'frame');
    while (FrameNode <> nil) and (FrameIdx < MaxSpriteFrames) do
    begin
      if not XMLHasAttr(FrameNode, 'x') or not XMLHasAttr(FrameNode, 'y') then
      begin
        LoadSPXError := 'Sprite "' + Sheet.Names[SprIdx] + '" frame missing x/y';
        FreeSPX(Sheet);
        XMLFreeTree(Root);
        Exit;
      end;

      Sheet.Sprites[SprIdx].Frames[FrameIdx].Rect.X := StrToInt(XMLAttr(FrameNode, 'x'));
      Sheet.Sprites[SprIdx].Frames[FrameIdx].Rect.Y := StrToInt(XMLAttr(FrameNode, 'y'));

      { Width/height: frame-level or sprite default }
      if XMLHasAttr(FrameNode, 'width') then
        Sheet.Sprites[SprIdx].Frames[FrameIdx].Rect.Width := StrToInt(XMLAttr(FrameNode, 'width'))
      else if HasDefSize then
        Sheet.Sprites[SprIdx].Frames[FrameIdx].Rect.Width := DefWidth
      else
      begin
        LoadSPXError := 'Sprite "' + Sheet.Names[SprIdx] + '" frame missing width';
        FreeSPX(Sheet);
        XMLFreeTree(Root);
        Exit;
      end;

      if XMLHasAttr(FrameNode, 'height') then
        Sheet.Sprites[SprIdx].Frames[FrameIdx].Rect.Height := StrToInt(XMLAttr(FrameNode, 'height'))
      else if HasDefSize then
        Sheet.Sprites[SprIdx].Frames[FrameIdx].Rect.Height := DefHeight
      else
      begin
        LoadSPXError := 'Sprite "' + Sheet.Names[SprIdx] + '" frame missing height';
        FreeSPX(Sheet);
        XMLFreeTree(Root);
        Exit;
      end;

      { Optional offsets }
      if XMLHasAttr(FrameNode, 'offset-x') then
        Sheet.Sprites[SprIdx].Frames[FrameIdx].OffsetX := StrToInt(XMLAttr(FrameNode, 'offset-x'))
      else
        Sheet.Sprites[SprIdx].Frames[FrameIdx].OffsetX := 0;

      if XMLHasAttr(FrameNode, 'offset-y') then
        Sheet.Sprites[SprIdx].Frames[FrameIdx].OffsetY := StrToInt(XMLAttr(FrameNode, 'offset-y'))
      else
        Sheet.Sprites[SprIdx].Frames[FrameIdx].OffsetY := 0;

      { Optional per-frame duration }
      if XMLHasAttr(FrameNode, 'duration') then
      begin
        Sheet.Sprites[SprIdx].Frames[FrameIdx].Duration := StrToReal(XMLAttr(FrameNode, 'duration'));
        HasAnyFrameDur := True;
      end
      else
        Sheet.Sprites[SprIdx].Frames[FrameIdx].Duration := 0.0;

      Inc(FrameIdx);
      FrameNode := XMLNextSibling(FrameNode, 'frame');
    end;

    Sheet.Sprites[SprIdx].FrameCount := FrameIdx;

    if FrameIdx = 0 then
    begin
      LoadSPXError := 'Sprite "' + Sheet.Names[SprIdx] + '" has no frames';
      FreeSPX(Sheet);
      XMLFreeTree(Root);
      Exit;
    end;

    { Set dimensions from sprite-level defaults or first frame }
    if HasDefSize then
    begin
      Sheet.Sprites[SprIdx].Width := DefWidth;
      Sheet.Sprites[SprIdx].Height := DefHeight;
    end
    else
    begin
      Sheet.Sprites[SprIdx].Width := Sheet.Sprites[SprIdx].Frames[0].Rect.Width;
      Sheet.Sprites[SprIdx].Height := Sheet.Sprites[SprIdx].Frames[0].Rect.Height;
    end;

    { Compute per-frame durations }
    Sheet.Sprites[SprIdx].HasFrameDurations := HasAnyFrameDur;
    if HasAnyFrameDur then
    begin
      DefaultDur := Sheet.Sprites[SprIdx].Duration / FrameIdx;
      TotalDur := 0.0;
      for I := 0 to FrameIdx - 1 do
      begin
        if Sheet.Sprites[SprIdx].Frames[I].Duration <= 0.0 then
          Sheet.Sprites[SprIdx].Frames[I].Duration := DefaultDur;
        TotalDur := TotalDur + Sheet.Sprites[SprIdx].Frames[I].Duration;
      end;
      Sheet.Sprites[SprIdx].TotalDuration := TotalDur;
    end
    else
      Sheet.Sprites[SprIdx].TotalDuration := 0.0;

    Inc(SprIdx);
    Child := XMLNextSibling(Child, 'sprite');
  end;

  Sheet.Count := SprIdx;
  XMLFreeTree(Root);
  LoadSPX := True;
end;

function GetSPXSprite(var Sheet: TSpriteSheet; const Name: String): PSprite;
var
  I: Byte;
begin
  GetSPXSprite := nil;
  for I := 0 to Sheet.Count - 1 do
  begin
    if Sheet.Names[I] = Name then
    begin
      GetSPXSprite := @Sheet.Sprites[I];
      Exit;
    end;
  end;
end;

procedure FreeSPX(var Sheet: TSpriteSheet);
begin
  if Sheet.Image.Data <> nil then
  begin
    FreeImage(Sheet.Image);
    Sheet.Image.Data := nil;
  end;
  Sheet.Count := 0;
end;

end.