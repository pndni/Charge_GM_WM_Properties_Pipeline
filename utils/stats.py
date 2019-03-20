import argparse
from collections.abc import Iterable
from functools import partial
import nibabel
import numpy as np
from scipy.ndimage import labeled_comprehension
from scipy import stats
import sys


def std(x):
    # this seems to mimic the fslstats std calculation
    if len(x) == 1:
        return 0.0
    else:
        return np.std(x, ddof=1)


def _flatten(x, out=None):
    if out is None:
        out = []
    for xt in x:
        if isinstance(xt, Iterable):
            _flatten(xt, out=out)
        else:
            out.append(xt)
    return out


class Append(argparse.Action):

    def __init__(self, option_strings, dest, nargs=0, function=None, **kwargs):
        if nargs != 0:
            raise ValueError('nargs must be 0 for Append action')
        if function is None:
            raise ValueError('function must be specified')
        self.function = function
        super().__init__(option_strings, dest, nargs=nargs, **kwargs)

    def __call__(self, parser, namespace, values, option_string):
        if not hasattr(namespace, 'statslist'):
            setattr(namespace, 'statslist', [])
        namespace.statslist.append(self.function)


def main(arglist=None):
    parser = argparse.ArgumentParser(description='Behaves like fslstats, but with different statistics.')
    parser.add_argument('-K', help='Label mask', nargs='?')
    parser.add_argument('input', help='Input image (nii or nii.gz)')
    parser.add_argument('-m', help='Mean', action=Append, function=np.mean)
    parser.add_argument('-s', help='Standard deviation', action=Append, function=std)
    parser.add_argument('--skew', action=Append, function=partial(stats.skew, axis=None))
    parser.add_argument('--kurtosis', action=Append, function=partial(stats.kurtosis, axis=None))
    parser.add_argument('--median', action=Append, function=np.median)
    parser.add_argument('--test', action='store_true')

    args = parser.parse_args(args=arglist)

    if args.test:
        test()
        return

    if not hasattr(args, 'statslist'):
        print('No stats requested', file=sys.stderr)

    def combine_stats(x):
        return _flatten([func(x) for func in args.statslist])

    input = nibabel.load(args.input).get_fdata()

    if args.K:
        mask = np.asanyarray(nibabel.load(args.K).dataobj)
        labels = [l for l in np.unique(mask) if l > 0]
        out = []
        for l in labels:
            out.extend([labeled_comprehension(input, mask, l, func, np.float, np.nan) for func in args.statslist])
    else:
        out = [func(input) for func in args.statslist]
    return out


def test():

    # create temp files
    import tempfile

    def gettmpfname():
        f = tempfile.NamedTemporaryFile(prefix='stats', suffix='.nii', delete=False)
        f.close()
        return f.name

    inputfile = gettmpfname()
    maskfile = gettmpfname()
    input = np.arange(3 * 4 * 5).reshape(3, 4, 5).astype(np.float)
    mask = np.zeros(input.shape, dtype=np.int)
    mask[:2, 0, -1] = 1
    mask[1, 1:3, 1:3] = 2
    mask[2, 1, 1] = 3
    assert tuple(np.unique(mask)) == (0, 1, 2, 3)
    nibabel.Nifti1Image(input, np.eye(4)).to_filename(inputfile)
    nibabel.Nifti1Image(mask, np.eye(4)).to_filename(maskfile)

    import subprocess

    def fslstats(input, statslist, usemask):
        cmd = ['fslstats']
        if usemask:
            cmd.append('-K')
            cmd.append(maskfile)
        cmd.append(inputfile)
        cmd.extend(statslist)
        out = subprocess.check_output(cmd).decode().split()
        return [float(o) for o in out]

    def mainwrap(input, statslist, usemask):
        cmd = []
        if usemask:
            cmd.append('-K')
            cmd.append(maskfile)
        cmd.append(inputfile)
        cmd.extend(statslist)
        return main(cmd)

    for m in [False, True]:
        assert np.allclose(fslstats(input, ['-m'], m), mainwrap(input, ['-m'], m))
        assert np.allclose(fslstats(input, ['-s'], m), mainwrap(input, ['-s'], m))
        assert np.allclose(fslstats(input, ['-m', '-s'], m), mainwrap(input, ['-m', '-s'], m))
        assert np.allclose(fslstats(input, ['-s', '-m'], m), mainwrap(input, ['-s', '-m'], m))


if __name__ == '__main__':
    out = main()
    if out is not None:
        print(' '.join([str(o) for o in out]))
