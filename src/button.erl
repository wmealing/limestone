-module(button).
-export([setup/1, is_pressed/1]).

%% The Pico uses 1 for high (released) and 0 for low (pressed) 
%% when using internal pull-up resistors.
-define(PRESSED, 0).
-define(RELEASED, 1).

-define(PIN, {wl, 0}).

%% @doc Initialize a GPIO pin for input with a pull-up resistor.
setup(_What) ->
    Pin = 15, 
    gpio:set_pin_mode(Pin, input), 
    gpio:set_pin_pull(Pin, up),
    ok.

%% @doc Returns true if the button is currently held down.
is_pressed(Pin) ->
    case gpio:digital_read(Pin) of
        high -> false;
        low  -> true
    end.
