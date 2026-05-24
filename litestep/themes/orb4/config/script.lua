orb = {
   x = 25.6,
   y = 23.45,
   r = 19.69,
}

do --mainly for an environment for the local vars
   local o,m,ex = orb,math,lslua.exec
   for i=0,59 do
       local x = o.x + o.r * m.cos ( ((i - 15) / 60) * 2 * m.pi)
       local y = o.y + o.r * m.sin ( ((i - 15) / 60) * 2 * m.pi)
       o [i] = function () ex ("!LabelMove OrbDot "..x.." "..y.." 2 1") end
   end
end

bang_minuteupdate = function (min) orb [tonumber (min)] () end;

function bang_orbcenter ()
    lslua.exec ("!LabelMove OrbMain ".. (lslua.mouse().x - 28) .." ".. (lslua.mouse().y - 28) .." 10 1")
    lslua.exec ("!LabelFocus OrbMain")
end