#
# Copyright 2020-2022 NXP
# Copyright 2024 Toradex
#
# SPDX-License-Identifier: Apache-2.0
#

import tflite_runtime.interpreter as tflite
from PIL import Image
import numpy as np
import cv2
import time, os
import argparse

from labels_som import label2string

MODEL_PATH = "/home/torizon/app/src/voc_som_eff2_30epoch.tflite"

parser = argparse.ArgumentParser()
parser.add_argument(
    '-i',
    '--input',
    default='/dev/video0',
    help='input to be classified')
parser.add_argument(
    '-d',
    '--delegate',
    default='',
    help='delegate path')
args = parser.parse_args()

vid = cv2.VideoCapture(args.input)

if(args.delegate):
    ext_delegate = [tflite.load_delegate(args.delegate)]
    interpreter = tflite.Interpreter(model_path=MODEL_PATH, experimental_delegates=ext_delegate)
else:
    interpreter = tflite.Interpreter(model_path=MODEL_PATH)
interpreter.allocate_tensors()

input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()
# NxHxWxC, H:1, W:2
height = input_details[0]['shape'][1]
width = input_details[0]['shape'][2]

msg = ""
total_fps = 0
total_time = 0

ret, frame = vid.read()
if (frame is None):
    print("Can't read frame from source file ", args.input)
    exit(0)

while ret:
    total_fps += 1
    loop_start = time.time()

    img = cv2.resize(frame, (width,height)).astype(np.uint8)
    input_data = np.expand_dims(img, axis=0)
    interpreter.set_tensor(input_details[0]['index'], input_data)

    invoke_start = time.time()
    interpreter.invoke()
    invoke_end = time.time()

    boxes = interpreter.get_tensor(output_details[1]['index'])[0]
    labels = interpreter.get_tensor(output_details[3]['index'])[0]
    scores = interpreter.get_tensor(output_details[0]['index'])[0]
    number = interpreter.get_tensor(output_details[2]['index'])[0]
    for i in range(int(number)):
        if scores[i] > 0.5:
            box = [boxes[i][0], boxes[i][1], boxes[i][2], boxes[i][3]]
            x0 = max(2, int(box[1] * frame.shape[1]))
            y0 = max(2, int(box[0] * frame.shape[0]))
            x1 = int(box[3] * frame.shape[1])
            y1 = int(box[2] * frame.shape[0])

            cv2.rectangle(frame, (x0, y0), (x1, y1), (255, 0, 0), 2)
            cv2.putText(frame, label2string[labels[i]], (x0, y0 + 13),
                        cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 3)
            print("rectangle:(%d,%d),(%d,%d) label:%s" % 
                    (x0, y0, x1, y1, label2string[labels[i]]))

    loop_end = time.time()
    total_time += (loop_end - loop_start)

    invoke_time_seg = (invoke_end - invoke_start)
    invoke_time_ms = invoke_time_seg * 1000
    fps = 1/invoke_time_seg
    msg = "FPS:" + "{:.2f}".format(fps) + "  Invoke time:" + "{:.2f}".format(invoke_time_ms) + "ms"
    cv2.putText(frame, msg, (0, 20), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 0), 3)

    #Name the GUI app
    cv2.namedWindow('object_detector',cv2.WINDOW_NORMAL)
    
    #Set the properties of GUI app
    cv2.setWindowProperty('object_detector', cv2.WND_PROP_FULLSCREEN,
                          cv2.WINDOW_FULLSCREEN)

    cv2.imshow("object_detector", frame)

    ret, frame = vid.read()
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

time.sleep(2)
vid.release()
cv2.destroyAllWindows()