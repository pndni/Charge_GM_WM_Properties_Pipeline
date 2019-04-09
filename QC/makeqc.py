import argparse
import os
import jinja2
import slicevol


WIDTH = 50  # em


def ensureunique(file_):
    if os.path.exists(file_):
        raise RuntimeError("{} exists".format(file_))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers()
    static = subparsers.add_parser('static')
    static.add_argument('name1', type=str)
    static.add_argument('imagefile1', type=str)
    static.add_argument('outdir', type=str)
    static.add_argument('--labelfile', type=str)
    static.add_argument('--logprefix', type=str)
    static.set_defaults(sub='static')
    fade = subparsers.add_parser('fade')
    fade.add_argument('name1', type=str)
    fade.add_argument('name2', type=str)
    fade.add_argument('imagefile1', type=str)
    fade.add_argument('imagefile2', type=str)
    fade.add_argument('outdir', type=str)
    fade.add_argument('--logprefix', type=str)
    fade.set_defaults(sub='fade')
    logs = subparsers.add_parser('logs')
    logs.add_argument('name1', type=str)
    logs.add_argument('logprefix', type=str)
    logs.add_argument('outdir', type=str)
    logs.set_defaults(sub='logs')
    args = parser.parse_args()
    templatevars = {'name1': args.name1}
    if args.sub == 'fade':
        templatevars['name2'] = args.name2
        outbase = os.path.join(args.outdir, args.name1 + "_" + args.name2)
        outbase1 = os.path.join(args.outdir, "{}-and-{}_{}".format(args.name1, args.name2, args.name1))
        outbase2 = os.path.join(args.outdir, "{}-and-{}_{}".format(args.name1, args.name2, args.name2))
    else:
        outbase = os.path.join(args.outdir, args.name1)
        outbase1 = outbase
    if args.logprefix is not None:
        for s in 'stdout', 'stderr':
            with open('{}_{}.txt'.format(args.logprefix, s), 'r') as f:
                templatevars[s] = f.read()
    if args.sub in ['static', 'fade']:
        for i, view in enumerate(['sagittal', 'coronal', 'axial']):
            if args.sub == 'static':
                labellist = []
                if args.labelfile:
                    labellist = ['{}::0.4'.format(args.labelfile)]
                outfile1 = '{}_{}.png'.format(outbase1, view)
                ensureunique(outfile1)
                arr = slicevol.create_slice([args.imagefile1], labellist, outfile1, isotropic=True, nslices=10, slicedim=i, approximate_iso=True)
                templatevars[view + "1"] = os.path.split(outfile1)[1]
            else:
                outfile1 = '{}_{}.png'.format(outbase1, view)
                outfile2 = '{}_{}.png'.format(outbase2, view)
                ensureunique(outfile1)
                ensureunique(outfile2)
                arr = slicevol.create_slice([args.imagefile1], [], outfile1, isotropic=True, nslices=10, slicedim=i, approximate_iso=True)
                slicevol.create_slice([args.imagefile2], [], outfile2, isotropic=True, nslices=10, slicedim=i, approximate_iso=True)
                templatevars[view + "1"] = os.path.split(outfile1)[1]
                templatevars[view + "2"] = os.path.split(outfile2)[1]
            templatevars["width_" + view] = "{}em".format(WIDTH)
            templatevars["height_" + view] = "{}em".format(WIDTH * arr.shape[0] / arr.shape[1])

    chargedir = os.getenv('CHARGEDIR')
    if chargedir is None:
        raise RuntimeError('CHARGEDIR is not set')
    env = jinja2.Environment(loader=jinja2.FileSystemLoader(os.path.join(chargedir, 'QC')))
    template = env.get_template('template.html')
    outname = '{}.html'.format(outbase)
    with open(outname, 'w') as f:
        print(template.render(**templatevars), file=f)
    print(outname)
