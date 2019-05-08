from collections import namedtuple
import argparse
from matplotlib.cm import ScalarMappable
from matplotlib.colors import Normalize, ListedColormap
import nibabel
import numpy as np
from imageio import imwrite


DEFAULT_CMAP = 'Greys_r'
DEFAULT_ALPHA = 1.0
ImageData = namedtuple('ImageData', ['imgs', 'cmap', 'alpha', 'vmin', 'vmax', 'affine', 'spacing'])


def _getslicelist(imgfile, slicedim, nslices):
    ni = nibabel.load(imgfile.split(':')[0])
    s = ni.shape[slicedim]
    slices_ = _calcslices(s, nslices)
    if slicedim == 1:
        slices_ = slices_[::-1]
    return slices_


def _calcslices(s, nslices):
    step = (s - 1) // (nslices - 1)
    last = (nslices - 1) * step
    offset = (s - last - 1) // 2
    last += offset
    start = offset
    return list(range(start, last + 1, step))


def _loadimage(imgstr, slicedim, slicenums, label=False):
    if imgstr is None:
        return None
    imgsplit = imgstr.split(':')
    name = imgsplit[0]
    ni = nibabel.load(name)
    img = ni.get_fdata()
    if img.ndim != 3:
        raise RuntimeError('Currently only 3d images supported')
    imgs = []
    for slicenum in slicenums:
        slices = [slice(None), slice(None), slice(None)]
        if slicenum is None:
            slicenum = img.shape[slicedim] // 2
        slices[slicedim] = slicenum
        imgtmp = img[tuple(slices)][::-1, ::-1].T
        imgs.append(imgtmp)
    imgs = np.array(imgs)
    affine = ni.affine
    spacing = list(np.sqrt(np.sum(affine[:3, :3] ** 2.0, axis=0)))
    spacing.pop(slicedim)
    spacing = spacing[::-1]  # to account for the transpose
    cmap, alpha, vmin, vmax = DEFAULT_CMAP, DEFAULT_ALPHA, np.min(imgs), np.max(imgs)
    if len(imgsplit) > 2:
        if imgsplit[2]:
            alpha = float(imgsplit[2])
    if label:
        cmap, N = _quantitativecmap()
        vmax = N + 1
        vmin = 1
        if len(np.unique(imgs)) - 1 > N:
            raise NotImplementedError('{} has too many labels for built in colormap'.format(imgstr))
    else:
        if len(imgsplit) > 1:
            if imgsplit[1]:
                cmap = imgsplit[1]
        if len(imgsplit) > 3:
            if imgsplit[3]:
                vmin = imgsplit[3]
        if len(imgsplit) > 4:
            if imgsplit[4]:
                vmax = imgsplit[4]
    return ImageData(imgs, cmap, alpha, vmin, vmax, affine, spacing)


def _plotimage(imagedata, out, i):
    sm = ScalarMappable(norm=Normalize(vmin=imagedata.vmin, vmax=imagedata.vmax), cmap=imagedata.cmap)
    nz = imagedata.imgs[i] > 0
    out[nz, :] = out[nz, :] * (1 - imagedata.alpha) + imagedata.alpha * sm.to_rgba(imagedata.imgs[i], bytes=False)[nz, :3]


def _make_isotropic(imgtmp, approximate=False):
    base = np.min(imgtmp.spacing)
    imgout = imgtmp.imgs
    for i, s in enumerate(imgtmp.spacing):
        f = s / base
        if not approximate and not np.allclose(f, np.around(f)):
            raise RuntimeError('Spacings are not integer multiples.')

        f = int(np.around(f))
        if f != 1:
            imgout = np.repeat(imgout, f, axis=i + 1)
    return imgtmp._replace(imgs=imgout)


def create_slice(bases, labels, outfile, slicedim=2, slicenums=None, isotropic=False, nslices=None, approximate_iso=False):
    if bases is None:
        bases = []
    if labels is None:
        labels = []
    if len(bases) == 0 and len(labels) == 0:
        raise RuntimeError('No images specified')
    if nslices is not None:
        if len(bases) > 0:
            first = bases[0]
        else:
            first = labels[0]
        slicenums = _getslicelist(first, slicedim, nslices)
    elif slicenums is None:
        slicenums = [None]
    imglist = []
    for base in bases:
        imglist.append(_loadimage(base, slicedim, slicenums))
    for label in labels:
        imglist.append(_loadimage(label, slicedim, slicenums, label=True))
    for imgtmp in imglist[1:]:
        if not np.allclose(imglist[0].affine, imgtmp.affine, atol=1e-6):
            raise RuntimeError('All images must have the same affine transformation')
        if imglist[0].imgs.shape != imgtmp.imgs.shape:
            raise RuntimeError('All images must have the same shape')
    if isotropic:
        imglist = [_make_isotropic(imgtmp, approximate=approximate_iso) for imgtmp in imglist]
    nslices, nrows, ncols = imglist[0].imgs.shape
    out = np.zeros((nrows, ncols * nslices, 3))
    for i in range(nslices):
        for imgtmp in imglist:
            _plotimage(imgtmp, out[:, i * ncols:(i + 1) * ncols, :], i)
    out = np.array(np.around(out * 255.0), dtype=np.uint8)
    imwrite(outfile, out)
    return out


def _quantitativecmap():
    # https://github.com/matplotlib/matplotlib/blob/master/lib/matplotlib/_cm.py
    _Set1_data = (
        (0.89411764705882357, 0.10196078431372549, 0.10980392156862745),
        (0.21568627450980393, 0.49411764705882355, 0.72156862745098038),
        (0.30196078431372547, 0.68627450980392157, 0.29019607843137257),
        (0.59607843137254901, 0.30588235294117649, 0.63921568627450975),
        (1.0,                 0.49803921568627452, 0.0                ),
        (1.0,                 1.0,                 0.2                ),
        (0.65098039215686276, 0.33725490196078434, 0.15686274509803921),
        (0.96862745098039216, 0.50588235294117645, 0.74901960784313726),
        (0.6,                 0.6,                 0.6),
        )

    _Set2_data = (
        (0.4,                 0.76078431372549016, 0.6470588235294118 ),
        (0.9882352941176471,  0.55294117647058827, 0.3843137254901961 ),
        (0.55294117647058827, 0.62745098039215685, 0.79607843137254897),
        (0.90588235294117647, 0.54117647058823526, 0.76470588235294112),
        (0.65098039215686276, 0.84705882352941175, 0.32941176470588235),
        (1.0,                 0.85098039215686272, 0.18431372549019609),
        (0.89803921568627454, 0.7686274509803922,  0.58039215686274515),
        (0.70196078431372544, 0.70196078431372544, 0.70196078431372544),
        )

    _Set3_data = (
        (0.55294117647058827, 0.82745098039215681, 0.7803921568627451 ),
        (1.0,                 1.0,                 0.70196078431372544),
        (0.74509803921568629, 0.72941176470588232, 0.85490196078431369),
        (0.98431372549019602, 0.50196078431372548, 0.44705882352941179),
        (0.50196078431372548, 0.69411764705882351, 0.82745098039215681),
        (0.99215686274509807, 0.70588235294117652, 0.3843137254901961 ),
        (0.70196078431372544, 0.87058823529411766, 0.41176470588235292),
        (0.9882352941176471,  0.80392156862745101, 0.89803921568627454),
        (0.85098039215686272, 0.85098039215686272, 0.85098039215686272),
        (0.73725490196078436, 0.50196078431372548, 0.74117647058823533),
        (0.8,                 0.92156862745098034, 0.77254901960784317),
        (1.0,                 0.92941176470588238, 0.43529411764705883),
    )
    colorlist = list(_Set1_data) + list(_Set2_data) + list(_Set3_data)
    return ListedColormap(colorlist), len(colorlist)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    slicegroup = parser.add_mutually_exclusive_group()
    parser.add_argument('out', type=str)
    parser.add_argument('--baseimages', type=str, nargs='*', default=[])
    parser.add_argument('--labelimages', type=str, nargs='*', default=[])
    parser.add_argument('--slicedim', type=int, default=2)
    slicegroup.add_argument('--slicenumbers', type=int, nargs='*', default=[None])
    slicegroup.add_argument('--nslices', type=int)
    parser.add_argument('--isotropic', action='store_true')
    args = parser.parse_args()
    create_slice(args.baseimages, args.labelimages, args.out,
                 slicedim=args.slicedim, slicenums=args.slicenumbers,
                 nslices=args.nslices, isotropic=args.isotropic)
