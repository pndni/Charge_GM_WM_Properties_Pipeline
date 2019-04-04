import nibabel
import numpy as np
import sys


def test_main():
    import tempfile
    import os

    def wrapper(arr):
        f = tempfile.NamedTemporaryFile(suffix='.nii', delete=False)
        f.close()
        nibabel.Nifti1Image(arr, affine=np.eye(4)).to_filename(f.name)
        out = main(f.name)
        os.remove(f.name)
        return out

    x = np.zeros((3, 3, 3))
    x[1, 1, 1] = 1
    assert not wrapper(x)
    x = np.zeros((3, 3, 3))
    x[0, 1, 1] = 1
    assert wrapper(x)
    x = np.zeros((3, 3, 3))
    x[1, 0, 1] = 1
    assert wrapper(x)
    x = np.zeros((3, 3, 3))
    x[1, 1, 0] = 1
    assert wrapper(x)
    x = np.zeros((3, 3, 3))
    x[-1, 1, 1] = 1
    assert wrapper(x)
    x = np.zeros((3, 3, 3))
    x[1, -1, 1] = 1
    assert wrapper(x)
    x = np.zeros((3, 3, 3))
    x[1, 1, -1] = 1
    assert wrapper(x)


def main(fname):
    ni = nibabel.load(fname)
    x = ni.get_fdata()
    assert x.ndim == 3
    return np.any(x[0, :, :] > 0.0) or np.any(x[-1, :, :] > 0.0) or np.any(x[:, 0, :] > 0.0) or np.any(x[:, -1, :] > 0.0) or np.any(x[:, :, 0] > 0.0) or np.any(x[:, :, -1] > 0.0)


if __name__ == '__main__':
    if main(sys.argv[1]):
        sys.exit("{} has nonzero boarder pixels. Aborting".format(sys.argv[1]))
