import os
import numpy as np
import tempfile, zipfile
import torch
import torch.nn as nn
import torch.nn.functional as F
try:
    import torchvision
    import torchaudio
except:
    pass

class Model(nn.Module):
    def __init__(self):
        super(Model, self).__init__()

        self.conv2d_0 = nn.Conv2d(bias=True, dilation=(1,1), groups=1, in_channels=3, kernel_size=(5,5), out_channels=8, padding=(0,0), padding_mode='zeros', stride=(1,1))
        self.conv2d_1 = nn.Conv2d(bias=True, dilation=(1,1), groups=1, in_channels=8, kernel_size=(3,3), out_channels=8, padding=(1,1), padding_mode='zeros', stride=(1,1))
        self.conv2d_2 = nn.Conv2d(bias=True, dilation=(1,1), groups=1, in_channels=8, kernel_size=(3,3), out_channels=16, padding=(1,1), padding_mode='zeros', stride=(1,1))
        self.conv2d_3 = nn.Conv2d(bias=True, dilation=(1,1), groups=1, in_channels=16, kernel_size=(3,3), out_channels=16, padding=(1,1), padding_mode='zeros', stride=(1,1))
        self.conv2d_4 = nn.Conv2d(bias=True, dilation=(1,1), groups=1, in_channels=16, kernel_size=(3,3), out_channels=32, padding=(1,1), padding_mode='zeros', stride=(1,1))
        self.conv2d_5 = nn.Conv2d(bias=True, dilation=(1,1), groups=1, in_channels=32, kernel_size=(3,3), out_channels=32, padding=(1,1), padding_mode='zeros', stride=(1,1))
        self.conv2d_6 = nn.Conv2d(bias=True, dilation=(1,1), groups=1, in_channels=32, kernel_size=(3,3), out_channels=48, padding=(1,1), padding_mode='zeros', stride=(1,1))
        self.conv2d_7 = nn.Conv2d(bias=True, dilation=(1,1), groups=1, in_channels=48, kernel_size=(3,3), out_channels=48, padding=(1,1), padding_mode='zeros', stride=(1,1))
        self.conv2d_8 = nn.Conv2d(bias=True, dilation=(1,1), groups=1, in_channels=48, kernel_size=(3,3), out_channels=64, padding=(1,1), padding_mode='zeros', stride=(1,1))
        self.conv2d_9 = nn.Conv2d(bias=True, dilation=(1,1), groups=1, in_channels=64, kernel_size=(3,3), out_channels=128, padding=(1,1), padding_mode='zeros', stride=(1,1))
        self.conv2d_10 = nn.Conv2d(bias=True, dilation=(1,1), groups=1, in_channels=128, kernel_size=(3,3), out_channels=12, padding=(0,0), padding_mode='zeros', stride=(2,2))
        self.conv2d_11 = nn.Conv2d(bias=True, dilation=(1,1), groups=1, in_channels=12, kernel_size=(1,1), out_channels=5, padding=(0,0), padding_mode='zeros', stride=(1,1))
        self.conv2d_12 = nn.Conv2d(bias=True, dilation=(1,1), groups=1, in_channels=128, kernel_size=(1,1), out_channels=78, padding=(0,0), padding_mode='zeros', stride=(1,1))

        archive = zipfile.ZipFile('F:\HarmonyOs\car\third_party\plate_open_source\weights\plate_rec_color.pnnx.bin', 'r')
        self.conv2d_0.bias = self.load_pnnx_bin_as_parameter(archive, 'conv2d_0.bias', (8), 'float32')
        self.conv2d_0.weight = self.load_pnnx_bin_as_parameter(archive, 'conv2d_0.weight', (8,3,5,5), 'float32')
        self.conv2d_1.bias = self.load_pnnx_bin_as_parameter(archive, 'conv2d_1.bias', (8), 'float32')
        self.conv2d_1.weight = self.load_pnnx_bin_as_parameter(archive, 'conv2d_1.weight', (8,8,3,3), 'float32')
        self.conv2d_2.bias = self.load_pnnx_bin_as_parameter(archive, 'conv2d_2.bias', (16), 'float32')
        self.conv2d_2.weight = self.load_pnnx_bin_as_parameter(archive, 'conv2d_2.weight', (16,8,3,3), 'float32')
        self.conv2d_3.bias = self.load_pnnx_bin_as_parameter(archive, 'conv2d_3.bias', (16), 'float32')
        self.conv2d_3.weight = self.load_pnnx_bin_as_parameter(archive, 'conv2d_3.weight', (16,16,3,3), 'float32')
        self.conv2d_4.bias = self.load_pnnx_bin_as_parameter(archive, 'conv2d_4.bias', (32), 'float32')
        self.conv2d_4.weight = self.load_pnnx_bin_as_parameter(archive, 'conv2d_4.weight', (32,16,3,3), 'float32')
        self.conv2d_5.bias = self.load_pnnx_bin_as_parameter(archive, 'conv2d_5.bias', (32), 'float32')
        self.conv2d_5.weight = self.load_pnnx_bin_as_parameter(archive, 'conv2d_5.weight', (32,32,3,3), 'float32')
        self.conv2d_6.bias = self.load_pnnx_bin_as_parameter(archive, 'conv2d_6.bias', (48), 'float32')
        self.conv2d_6.weight = self.load_pnnx_bin_as_parameter(archive, 'conv2d_6.weight', (48,32,3,3), 'float32')
        self.conv2d_7.bias = self.load_pnnx_bin_as_parameter(archive, 'conv2d_7.bias', (48), 'float32')
        self.conv2d_7.weight = self.load_pnnx_bin_as_parameter(archive, 'conv2d_7.weight', (48,48,3,3), 'float32')
        self.conv2d_8.bias = self.load_pnnx_bin_as_parameter(archive, 'conv2d_8.bias', (64), 'float32')
        self.conv2d_8.weight = self.load_pnnx_bin_as_parameter(archive, 'conv2d_8.weight', (64,48,3,3), 'float32')
        self.conv2d_9.bias = self.load_pnnx_bin_as_parameter(archive, 'conv2d_9.bias', (128), 'float32')
        self.conv2d_9.weight = self.load_pnnx_bin_as_parameter(archive, 'conv2d_9.weight', (128,64,3,3), 'float32')
        self.conv2d_10.bias = self.load_pnnx_bin_as_parameter(archive, 'conv2d_10.bias', (12), 'float32')
        self.conv2d_10.weight = self.load_pnnx_bin_as_parameter(archive, 'conv2d_10.weight', (12,128,3,3), 'float32')
        self.conv2d_11.bias = self.load_pnnx_bin_as_parameter(archive, 'conv2d_11.bias', (5), 'float32')
        self.conv2d_11.weight = self.load_pnnx_bin_as_parameter(archive, 'conv2d_11.weight', (5,12,1,1), 'float32')
        self.conv2d_12.bias = self.load_pnnx_bin_as_parameter(archive, 'conv2d_12.bias', (78), 'float32')
        self.conv2d_12.weight = self.load_pnnx_bin_as_parameter(archive, 'conv2d_12.weight', (78,128,1,1), 'float32')
        archive.close()

    def load_pnnx_bin_as_parameter(self, archive, key, shape, dtype, requires_grad=True):
        return nn.Parameter(self.load_pnnx_bin_as_tensor(archive, key, shape, dtype), requires_grad)

    def load_pnnx_bin_as_tensor(self, archive, key, shape, dtype):
        fd, tmppath = tempfile.mkstemp()
        with os.fdopen(fd, 'wb') as tmpf, archive.open(key) as keyfile:
            tmpf.write(keyfile.read())
        m = np.memmap(tmppath, dtype=dtype, mode='r', shape=shape).copy()
        os.remove(tmppath)
        return torch.from_numpy(m)

    def forward(self, v_0):
        v_1 = self.conv2d_0(v_0)
        v_2 = F.relu(v_1)
        v_3 = self.conv2d_1(v_2)
        v_4 = F.relu(v_3)
        v_5 = self.conv2d_2(v_4)
        v_6 = F.relu(v_5)
        v_7 = self.conv2d_3(v_6)
        v_8 = F.relu(v_7)
        v_9 = F.max_pool2d(v_8, ceil_mode=True, dilation=(1,1), kernel_size=(3,3), padding=(0,0), return_indices=False, stride=(2,2))
        v_10 = self.conv2d_4(v_9)
        v_11 = F.relu(v_10)
        v_12 = self.conv2d_5(v_11)
        v_13 = F.relu(v_12)
        v_14 = F.max_pool2d(v_13, ceil_mode=True, dilation=(1,1), kernel_size=(3,3), padding=(0,0), return_indices=False, stride=(2,2))
        v_15 = self.conv2d_6(v_14)
        v_16 = F.relu(v_15)
        v_17 = self.conv2d_7(v_16)
        v_18 = F.relu(v_17)
        v_19 = F.max_pool2d(v_18, ceil_mode=True, dilation=(1,1), kernel_size=(3,3), padding=(0,0), return_indices=False, stride=(2,2))
        v_20 = self.conv2d_8(v_19)
        v_21 = F.relu(v_20)
        v_22 = self.conv2d_9(v_21)
        v_23 = F.relu(v_22)
        v_24 = self.conv2d_10(v_23)
        v_25 = F.relu(v_24)
        v_26 = self.conv2d_11(v_25)
        v_27 = F.adaptive_avg_pool2d(v_26, output_size=(1,1))
        v_28 = torch.flatten(v_27, end_dim=-1, start_dim=1)
        v_29 = F.max_pool2d(v_23, ceil_mode=False, dilation=(1,1), kernel_size=(5,2), padding=(0,1), return_indices=False, stride=(1,1))
        v_30 = self.conv2d_12(v_29)
        v_31 = torch.squeeze(v_30, dim=2)
        v_32 = v_31.permute(dims=(0,2,1))
        return v_32, v_28

def export_torchscript():
    net = Model()
    net.float()
    net.eval()

    torch.manual_seed(0)
    v_0 = torch.rand(1, 3, 48, 168, dtype=torch.float)

    mod = torch.jit.trace(net, v_0)
    mod.save("F:\HarmonyOs\car\third_party\plate_open_source\weights\plate_rec_color_pnnx.py.pt")

def export_onnx():
    net = Model()
    net.float()
    net.eval()

    torch.manual_seed(0)
    v_0 = torch.rand(1, 3, 48, 168, dtype=torch.float)

    torch.onnx.export(net, v_0, "F:\HarmonyOs\car\third_party\plate_open_source\weights\plate_rec_color_pnnx.py.onnx", export_params=True, operator_export_type=torch.onnx.OperatorExportTypes.ONNX_ATEN_FALLBACK, opset_version=13, input_names=['in0'], output_names=['out0', 'out1'])

def export_pnnx():
    net = Model()
    net.float()
    net.eval()

    torch.manual_seed(0)
    v_0 = torch.rand(1, 3, 48, 168, dtype=torch.float)

    import pnnx
    pnnx.export(net, "F:\HarmonyOs\car\third_party\plate_open_source\weights\plate_rec_color_pnnx.py.pt", v_0)

def export_ncnn():
    export_pnnx()

@torch.no_grad()
def test_inference():
    net = Model()
    net.float()
    net.eval()

    torch.manual_seed(0)
    v_0 = torch.rand(1, 3, 48, 168, dtype=torch.float)

    return net(v_0)

if __name__ == "__main__":
    print(test_inference())
