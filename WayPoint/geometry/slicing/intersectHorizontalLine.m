function xInts = intersectHorizontalLine(poly, y)

xInts = [];

for i = 1:size(poly,1)-1

    p1 = poly(i,:);
    p2 = poly(i+1,:);

    if (p1(2) <= y && p2(2) > y) || (p2(2) <= y && p1(2) > y)

        t = (y - p1(2)) / (p2(2) - p1(2));
        x = p1(1) + t*(p2(1) - p1(1));
        xInts(end+1) = x; %#ok<AGROW>
    end
end
end