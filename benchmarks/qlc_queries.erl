-module(qlc_queries).

-include_lib("stdlib/include/qlc.hrl").

-export([get/2]).

get(Table, Id) ->
    Handle = qlc:q([X || X <- mnesia:table(Table), element(2, X) == Id ]),
    qlc:e(Handle).
