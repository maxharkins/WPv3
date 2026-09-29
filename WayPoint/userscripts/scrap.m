im1_fp = "C:\Users\SCIENTIFICA\Box\Zhang&Brown\Experiments\2026\2026-04-28_experiment-name\raw\before-image_20260428215448325_zm1_pdt3200ns_w512px_h512px_z101um_stk100step5to150um_pow0p3_ch3_fps1p07_00001.tif";
im2_fp = "C:\Users\SCIENTIFICA\Box\Zhang&Brown\Experiments\2026\2026-04-28_experiment-name\raw\after-image_20260428215448325_zm1_pdt3200ns_w512px_h512px_z103um_stk100step5to150um_pow0p3_ch3_fps1p07_00001.tif";
im3_fp = "C:\Users\SCIENTIFICA\Box\Zhang&Brown\Experiments\2026\2026-04-28_experiment-name\raw\after-image_20260428215448325_zm1_pdt3200ns_w512px_h512px_z103um_stk100step5to150um_pow0p3_ch3_fps1p07_0002_00001.tif";
im4_fp = "C:\Users\SCIENTIFICA\Box\Zhang&Brown\Experiments\2026\2026-04-28_experiment-name\raw\after-image_20260428215448325_zm1_pdt3200ns_w512px_h512px_z103um_stk100step5to150um_pow0p3_ch3_fps1p07_0003_00001.tif";

im1 = tiffreadVolume(im1_fp);
im2 = tiffreadVolume(im2_fp);
im3 = tiffreadVolume(im3_fp);
im4 = tiffreadVolume(im4_fp);

im_new = im1 - im4;

imshow(im_new(:,:,6), [])