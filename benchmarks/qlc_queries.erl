-module(qlc_queries).

-include_lib("stdlib/include/qlc.hrl").

-export([get/2, get_int_idx/2, get_string_idx/2, get_int_non_idx/2, get_string_non_idx/2]).

get(Table, Id) ->
    Handle = qlc:q([X || X <- mnesia:table(Table), element(2, X) == Id ]),
    qlc:e(Handle).

get_int_idx(Table, I) ->
    Handle = qlc:q([X || X <- mnesia:table(Table), element(3, X) == I ]),
    qlc:e(Handle).

get_string_idx(Table, S) ->
    Handle = qlc:q([X || X <- mnesia:table(Table), element(4, X) == S ]),
    qlc:e(Handle).

get_int_non_idx(Table, I) ->
    Handle = qlc:q([X || X <- mnesia:table(Table), element(4, X) == I ]),
    qlc:e(Handle).

get_string_non_idx(Table, S) ->
    Handle = qlc:q([X || X <- mnesia:table(Table), element(6, X) == S ]),
    qlc:e(Handle).
