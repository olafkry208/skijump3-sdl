unit SDLPort;

interface

  type TPalette = Array[0..255,0..2] of byte;
  type SInt32 = LongInt;
  type TSDL_KeyCode = SInt32;

  function GetVersion : string;

  procedure Init;
  procedure DeinitGraphics;
  procedure Deinit;

  procedure SetPalette(input : TPalette);
  procedure Render(buffer : array of byte);
  procedure WaitRaster;

  function KeyPressed : boolean;
  function WaitForKeyPress : TSDL_KeyCode;

  procedure Wait(ms : integer);

implementation

  uses sdl2;
  const version: string = 'SP2';
        xRes = 320;
        yRes = 200;
        targetFrames = 70;
        aspect: real = xRes / yRes;

  var windowMultiplier: integer;
      window: PSDL_Window;
      renderer: PSDL_Renderer;
      originalSurface: PSDL_Surface;
      displaySurface: PSDL_Surface;
      displayTexture: PSDL_Texture;
      palette: array[0..255] of TSDL_Color;
      renderDestRect: TSDL_Rect;

      windowResized: boolean;
      fullScreen: boolean;

      timer: TSDL_TimerID;
      frameCount, lastFrameCount, subFrameCount, lastFrameTick: LongInt;

function TimerCallback(interval: UInt32; param: Pointer): UInt32; cdecl;
var frameIntervalMs, nowMs : LongInt;
begin
  frameIntervalMs := 1000 div targetFrames;
  nowMs := SDL_GetTicks();
  subFrameCount += nowMs - lastFrameTick;
  lastFrameTick := nowMs;

  while (subFrameCount >= frameIntervalMs) do
  begin
    dec(subFrameCount, frameIntervalMs);
    inc(framecount);
  end;

  TimerCallback:=interval;
end;

procedure GetRenderRect(var rect : TSDL_Rect);
var windowW, windowH, h, w: LongInt;
begin
  SDL_GetRendererOutputSize(renderer, @windowW, @windowH);
  if (windowW / windowH <= aspect) then
  begin
    h := round(windowW / aspect);
    rect.x := 0;
    rect.y := (windowH - h) div 2;
    rect.w := windowW;
    rect.h := h;
  end
  else
  begin
    w := round(windowH * aspect);
    rect.x := (windowW - w) div 2;
    rect.y := 0;
    rect.w := w;
    rect.h := windowH;
  end;
end;

procedure RefreshRendering;
begin
  GetRenderRect(renderDestRect);
end;

procedure ResetWindowSize;
begin
  SDL_SetWindowSize(window, xRes * windowMultiplier, yRes * windowMultiplier);
  windowResized := true;
end;

function GetVersion: string;
begin
  GetVersion := version;
end;

procedure Init;
begin
  windowMultiplier := 2;

  if SDL_Init( SDL_INIT_VIDEO or SDL_INIT_TIMER ) < 0 then HALT;

  window := SDL_CreateWindow('Ski Jump International v3',
            SDL_WINDOWPOS_UNDEFINED,
            SDL_WINDOWPOS_UNDEFINED,
            xRes * windowMultiplier,
            yRes * windowMultiplier,
            SDL_WINDOW_SHOWN or SDL_WINDOW_RESIZABLE);
  if window = nil then Halt;

  renderer := SDL_CreateRenderer(window, -1, 0);
  if renderer = nil then Halt;

  // 8-bit surface for original data
  originalSurface := SDL_CreateRGBSurface(0, xRes, yRes, 8, 0, 0, 0, 0);
  if originalSurface = nil then Halt;

  // 32-bit display surface for converting 8-bit data to 32-bit
  displaySurface := SDL_CreateRGBSurface(0, xRes, yRes, 32, 0, 0, 0, 0);
  if displaySurface = nil then Halt;

  // Finally a texture for displaying 32-bit display data
  displayTexture := SDL_CreateTexture(renderer,
                 SDL_PIXELFORMAT_RGBA8888,
                 SDL_TEXTUREACCESS_STREAMING,
                 xRes,
                 yRes);
  if displayTexture = nil then Halt;

  RefreshRendering();

  windowResized := false;
  fullScreen := false;

  frameCount := 0;
  lastFrameCount := 0;
  subFrameCount := 0;
  lastFrameTick := SDL_GetTicks();

  timer := SDL_AddTimer(1, TimerCallback, nil);
end;

procedure DeinitGraphics;
begin
  SDL_RemoveTimer(timer);
  SDL_FreeSurface(originalSurface);
  SDL_FreeSurface(displaySurface);
  SDL_DestroyTexture(displayTexture);
  SDL_DestroyRenderer(renderer);
  SDL_DestroyWindow(window);
end;

procedure Deinit;
begin
  SDL_Quit;
end;

procedure SetPalette(input : TPalette);
var index : integer;
begin
  for index:=0 to 255 do
   begin
     palette[index].r:=input[index,0] shl 2;
     palette[index].g:=input[index,1] shl 2;
     palette[index].b:=input[index,2] shl 2;
  end;

  SDL_SetPaletteColors(originalSurface^.format^.palette, @palette, 0, 256);
end;

procedure Render(buffer : array of byte);
var pixels : Pointer;
    pitch : LongInt;
begin
  if (windowResized) then
  begin
    RefreshRendering();
    windowResized := false;
  end;

  SDL_RenderClear(renderer);

  // Actual rendering
  SDL_LockSurface(originalSurface);
  Move(buffer, originalSurface^.pixels^, Sizeof(buffer));
  SDL_UnlockSurface(originalSurface);

  // Blit 8-bit surface to 32-bit surface
  SDL_BlitSurface(originalSurface, nil, displaySurface, nil);

  // Surface to texture
  SDL_LockTexture(displayTexture, nil, @pixels, @pitch);

  SDL_ConvertPixels(displaySurface^.w, displaySurface^.h,
                    displaySurface^.format^.format,
                    displaySurface^.pixels, displaySurface^.pitch,
                    SDL_PIXELFORMAT_RGBA8888,
                    pixels, pitch);

  SDL_UnlockTexture(displayTexture);

  // Render texture to display
  SDL_RenderCopy(renderer, displayTexture, nil, @renderDestRect);
  SDL_RenderPresent(renderer);
end;

procedure WaitRaster;
begin
  while(lastFrameCount = framecount) do
  begin
    SDL_Delay(1);
  end;
  lastFrameCount := framecount;
end;

function KeyPressed : boolean;
var event : TSDL_Event;
    pressed: boolean;
begin
  pressed:=false;

  while SDL_PollEvent(@event) = 1 do
  begin
    if ((event.type_= SDL_WINDOWEVENT) and
     (event.window.event = SDL_WINDOWEVENT_RESIZED)) then
    begin
      windowResized := true;
    end;

    if (event.type_= SDL_QUITEV) then
    begin
      Halt;
    end;

    if event.type_= SDL_KEYDOWN then
    begin
      // Ignore modifier and status keys, since they did not trigger a keypress in DOS version.
      // F11, F12 and probably others were ignored too, but that would probably be counterintuitive.
      case event.key.keysym.sym of
        SDLK_LCTRL, SDLK_RCTRL,
        SDLK_LSHIFT, SDLK_RSHIFT,
        SDLK_LALT, SDLK_RALT,
        SDLK_LGUI, SDLK_RGUI,
        SDLK_CAPSLOCK, SDLK_SCROLLLOCK, SDLK_NUMLOCKCLEAR,
        SDLK_PRINTSCREEN, SDLK_SYSREQ, SDLK_PAUSE:
        ; // Keypress ignored
      else
        begin
          pressed:=true;
          SDL_PushEvent(@event);
          break;
        end;
      end;
    end;
  end;
  KeyPressed:=pressed
end;

procedure ToggleFullscreen;
var flags : UInt32;
begin
  windowResized := true;

  fullScreen := not fullScreen;
  if (fullScreen) then flags := SDL_WINDOW_FULLSCREEN_DESKTOP else flags := 0;

  SDL_SetWindowFullscreen(window, flags);
end;

function WaitForKeyPress : TSDL_KeyCode;
var event : TSDL_Event;
    scancode: TSDL_ScanCode;
    keyPressed: TSDL_KeyCode;
    keyMod: UInt16;
begin
  keyPressed:=TSDL_KeyCode(0);

  while (true) do
  begin
    while SDL_PollEvent(@event) = 1 do
    begin
      if event.type_= SDL_KEYDOWN then
      begin
        scancode := event.key.keysym.scancode;
        keyPressed := event.key.keysym.sym;
        keyMod := event.key.keysym._mod;

        // SDL version specific shortcuts
        if ((keyMod and KMOD_LALT) > 0) then
        begin
          Case keyPressed of
            SDLK_RETURN :
              begin
                toggleFullscreen;
                exit
              end;
            SDLK_r :
              begin
                ResetWindowSize;
                exit
              end;
            SDLK_KP_PLUS, SDLK_EQUALS :
              begin
                windowMultiplier := windowMultiplier + 1;
                ResetWindowSize;
                exit
              end;
            SDLK_KP_MINUS, SDLK_MINUS :
              begin
                if (windowMultiplier > 1) then
                begin
                  windowMultiplier := windowMultiplier - 1;
                  ResetWindowSize;
                  exit
                end;
              end;
          end;
        end;

        // Ignore modifier and status keys, since they did not trigger a keypress in DOS version.
        // F11, F12 and probably others were ignored too, but that would probably be counterintuitive.
        case event.key.keysym.sym of
          SDLK_LCTRL, SDLK_RCTRL,
          SDLK_LSHIFT, SDLK_RSHIFT,
          SDLK_LALT, SDLK_RALT,
          SDLK_LGUI, SDLK_RGUI,
          SDLK_CAPSLOCK, SDLK_SCROLLLOCK, SDLK_NUMLOCKCLEAR,
          SDLK_PRINTSCREEN, SDLK_SYSREQ, SDLK_PAUSE:
            continue; // Keypress ignored
        end;

        // Special cases for key combinations used throughout the game.
        // Check for Right Alt/AltGr first, since pressing it can make Left Ctrl look as pressed too.
        if ((keyMod and KMOD_MODE) > 0) then exit;
        if ((keyMod and KMOD_RALT) > 0) then exit;
        if ((keyMod and KMOD_LALT) > 0) then
        begin
          Case keyPressed of
            SDLK_x: begin exit end; { TODO: ALT-X }
          else
            exit
          end;
        end;
        if ((keyMod and KMOD_CTRL) > 0) then
        begin
          Case keyPressed of
            SDLK_c: begin exit end; { TODO: CTRL-C }
          else
            exit
          end;
        end;
        if ((keyMod and KMOD_GUI) > 0) then exit;

        // If modifier is Shift, convert the key pressed accordingly.
        // For special keys, standard US QWERTY layout is assumed.
        if ((keyMod and KMOD_SHIFT) > 0) then
        begin
          Case keyPressed of
            SDLK_1 : keyPressed:=SDLK_EXCLAIM;
            SDLK_2 : keyPressed:=SDLK_AT;
            SDLK_3 : keyPressed:=SDLK_HASH;
            SDLK_4 : keyPressed:=SDLK_DOLLAR;
            SDLK_5 : keyPressed:=SDLK_PERCENT;
            SDLK_6 : keyPressed:=SDLK_CARET;
            SDLK_7 : keyPressed:=SDLK_AMPERSAND;
            SDLK_8 : keyPressed:=SDLK_ASTERISK;
            SDLK_9 : keyPressed:=SDLK_LEFTPAREN;
            SDLK_0 : keyPressed:=SDLK_RIGHTPAREN;
            SDLK_MINUS : keyPressed:=SDLK_UNDERSCORE;
            SDLK_EQUALS : keyPressed:=SDLK_PLUS;
            SDLK_LEFTBRACKET : keyPressed:=TSDL_KeyCode('{');
            SDLK_RIGHTBRACKET : keyPressed:=TSDL_KeyCode('}');
            SDLK_SEMICOLON : keyPressed:=SDLK_COLON;
            {SDLK_QUOTE} TSDL_KeyCode('''') : keyPressed:=SDLK_QUOTEDBL; // bug in ev1313/Pascal-SDL-2-Headers - wrong value of SDLK_QUOTE
            SDLK_BACKQUOTE : keyPressed:=TSDL_KeyCode('~');
            SDLK_BACKSLASH : keyPressed:=TSDL_KeyCode('|');
            SDLK_COMMA : keyPressed:=SDLK_LESS;
            SDLK_PERIOD : keyPressed:=SDLK_GREATER;
            SDLK_SLASH : keyPressed:=SDLK_QUESTION;
          end;
        end;

        // If NumLock modifier is not set, convert the charaters accordingly
        if ((keyMod and KMOD_NUM) = 0) then
        begin
          Case keyPressed of
            SDLK_KP_1 : keyPressed:=SDLK_END;
            SDLK_KP_2 : keyPressed:=SDLK_DOWN;
            SDLK_KP_3 : keyPressed:=SDLK_PAGEDOWN;
            SDLK_KP_4 : keyPressed:=SDLK_LEFT;
            SDLK_KP_5 : ;
            SDLK_KP_6 : keyPressed:=SDLK_RIGHT;
            SDLK_KP_7 : keyPressed:=SDLK_HOME;
            SDLK_KP_8 : keyPressed:=SDLK_UP;
            SDLK_KP_9 : keyPressed:=SDLK_PAGEUP;
            SDLK_KP_0 : keyPressed:=SDLK_INSERT;
            SDLK_KP_PERIOD : keyPressed:=SDLK_DELETE;
          end;
        end;
        
        // Merge keypad characters with their regular counterparts.
        // It is not needed to differentiate between them, since the scancode isn't checked for normal characters.
        // Checks for Shift and Num Lock were already done, so they won't interfere with the merge.
        Case keyPressed of
          SDLK_KP_DIVIDE : keyPressed:=SDLK_SLASH;
          SDLK_KP_MULTIPLY : keyPressed:=SDLK_ASTERISK;
          SDLK_KP_MINUS : keyPressed:=SDLK_MINUS;
          SDLK_KP_PLUS : keyPressed:=SDLK_PLUS;
          SDLK_KP_ENTER : keyPressed:=SDLK_RETURN;
          SDLK_KP_1 : keyPressed:=SDLK_1;
          SDLK_KP_2 : keyPressed:=SDLK_2;
          SDLK_KP_3 : keyPressed:=SDLK_3;
          SDLK_KP_4 : keyPressed:=SDLK_4;
          SDLK_KP_5 : keyPressed:=SDLK_5;
          SDLK_KP_6 : keyPressed:=SDLK_6;
          SDLK_KP_7 : keyPressed:=SDLK_7;
          SDLK_KP_8 : keyPressed:=SDLK_8;
          SDLK_KP_9 : keyPressed:=SDLK_9;
          SDLK_KP_0 : keyPressed:=SDLK_0;
          SDLK_KP_PERIOD : keyPressed:=SDLK_PERIOD;
          SDLK_KP_EQUALS : keyPressed:=SDLK_EQUALS;
        end;

        WaitForKeyPress := keyPressed;
        exit;
      end;
    end;
    SDL_Delay(10);
  end;
end;

procedure Wait(ms : integer);
begin
  SDL_Delay(ms);
end;

end.

