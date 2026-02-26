function init3Dplot(obj)

    hold(obj.Axes_XYZ, 'on');
    xlabel(obj.Axes_XYZ, 'X-axis');
    ylabel(obj.Axes_XYZ, 'Y-axis');
    zlabel(obj.Axes_XYZ, 'Z-axis');
    view(obj.Axes_XYZ, 3);

    xlim(obj.Axes_XYZ, [-3000, 3000]);
    ylim(obj.Axes_XYZ, [-3000, 3000]);
    zlim(obj.Axes_XYZ, [-50, 50]);

    axis(obj.Axes_XYZ, 'off');
    obj.Axes_XYZ.Clipping = 'off';
    set(obj.Axes_XYZ, 'ZDir', 'reverse')

end