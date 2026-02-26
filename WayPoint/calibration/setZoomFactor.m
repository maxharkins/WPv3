function setZoomFactor(hSICtl, targetZoomFactor)
    
    tensValue = floor(targetZoomFactor/10);
    onesValue = floor(mod(targetZoomFactor,10));
    fracValue = floor(mod(targetZoomFactor*10,10));
    
    hSICtl.hGUIData.mainControlsV4.zoomtens.String = tensValue;
    hSICtl.changeScanZoomFactorForEdit(hSICtl.hGUIData.mainControlsV4.zoomtensslider, 10, hSICtl.hGUIData.mainControlsV4)
    
    hSICtl.hGUIData.mainControlsV4.zoomones.String = onesValue;
    hSICtl.changeScanZoomFactorForEdit(hSICtl.hGUIData.mainControlsV4.zoomonesslider, 01, hSICtl.hGUIData.mainControlsV4)
    
    hSICtl.hGUIData.mainControlsV4.zoomfrac.String = fracValue;
    hSICtl.changeScanZoomFactorForEdit(hSICtl.hGUIData.mainControlsV4.zoomfracslider, .1, hSICtl.hGUIData.mainControlsV4)

end