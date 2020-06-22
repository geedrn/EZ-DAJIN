import os

os.environ["TF_CPP_MIN_LOG_LEVEL"] = "3"
os.environ["TF_FORCE_GPU_ALLOW_GROWTH"] = "true"

import sys
import numpy as np
import pandas as pd
import swifter
import dask.dataframe as dd

from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder, LabelBinarizer
from sklearn.neighbors import LocalOutlierFactor

import tensorflow as tf
from tensorflow.keras import regularizers
from tensorflow.keras.layers import Conv1D, Dense, Flatten, MaxPooling1D
from tensorflow.keras.callbacks import EarlyStopping
from tensorflow.keras.models import Model

################################################################################
#! I/O naming
################################################################################

# ===========================================================
# ? TEST auguments
# ===========================================================

# file_name = ".DAJIN_temp/data/DAJIN_MIDS.txt"
# mutation_type = "P"
# threads = 65

# ===========================================================
# ? Auguments
# ===========================================================

args = sys.argv
file_name = args[1]
mutation_type = args[2]
threads = int(args[3])

if mutation_type == "":
    raise ValueError("mutation_type is empty")

if threads == "":
    threads = 1

# ===========================================================
# ? Input
# ===========================================================

# df = pd.read_csv(file_name, header=None, sep="\t")
df = dd.read_csv(file_name, header=None, sep="\t")
# df = dd.from_pandas(pd.read_csv(file_name, header=None, sep="\t"), npartitions=threads)
df.columns = ["seqID", "seq", "barcodeID"]
df.seq = "MIDS=" + df.seq

df_sim = df[df.barcodeID.str.contains("simulated")].reset_index(drop=True)
df_real = df[~df.barcodeID.str.contains("simulated")].reset_index(drop=True)

del df  # <<<

################################################################################
#! Training model
################################################################################

# ===========================================================
# ? Encording Function
# ===========================================================


def label_encorde_seq(seq):
    label_seq = (
        seq.apply(list).apply(LabelEncoder().fit_transform).apply(pd.Series).to_numpy()
    )
    return label_seq


def onehot_encode_seq(seq):
    onehot_seq = np.apply_along_axis(
        LabelBinarizer().fit_transform, 1, label_encorde_seq(seq)
    ).astype(np.uint8)
    return onehot_seq


# from sklearn.preprocessing import OneHotEncoder
# def one_hot_encoder(my_array):
#     integer_encoded = label_encoder.transform(my_array)
#     onehot_encoder = OneHotEncoder(sparse=False, dtype=int, n_values=5)
#     integer_encoded = integer_encoded.reshape(len(integer_encoded), 1)
#     onehot_encoded = onehot_encoder.fit_transform(integer_encoded)
#     onehot_encoded = np.delete(onehot_encoded, -1, 1)
#     return onehot_encoded

# ===========================================================
# ? Train test split
# ===========================================================

labels, labels_index = pd.factorize(df_sim.barcodeID)
labels = tf.keras.utils.to_categorical(labels)

X_train, X_test, Y_train, Y_test = train_test_split(
    onehot_encode_seq(df_sim.seq.compute()), labels, test_size=0.2, shuffle=True
)

del X_test
del Y_test

# ===========================================================
# ? L2-constrained Softmax Loss
# ===========================================================
model = tf.keras.Sequential()
model.add(
    Conv1D(
        filters=16,
        kernel_size=32,
        activation="relu",
        input_shape=(X_train.shape[1], X_train.shape[2]),
        name="1st_Conv1D",
    )
)
model.add(MaxPooling1D(pool_size=4, name="1st_MaxPooling1D"))
model.add(Conv1D(filters=32, kernel_size=16, activation="relu", name="2nd_Conv1D"))
model.add(MaxPooling1D(pool_size=4, name="2nd_MaxPooling1D"))
model.add(Conv1D(filters=64, kernel_size=8, activation="relu", name="3rd_Conv1D"))
model.add(MaxPooling1D(pool_size=4, name="3rd_MaxPooling1D"))
model.add(Conv1D(filters=128, kernel_size=4, activation="relu", name="4th_Conv1D"))
model.add(MaxPooling1D(pool_size=4, name="4th_MaxPooling1D"))
model.add(Flatten(name="flatten"))
# model.add(Dense(64, activation='relu', name="1st_FC"))
alpha = 0.1
model.add(
    Dense(
        32,
        activation="linear",
        activity_regularizer=regularizers.l2(alpha),
        name="L2-softmax",
    )
)
model.add(Dense(len(labels_index), activation="softmax", name="final_layer"))
model.compile(optimizer="adam", loss="categorical_crossentropy", metrics=["accuracy"])

# ===========================================================
# ? Training
# ===========================================================

model.fit(
    X_train,
    Y_train,
    epochs=20,
    verbose=1,
    batch_size=32,
    validation_split=0.2,
    shuffle=True,
)

################################################################################
#! Novelity (Anomaly) detection
################################################################################
# ===========================================================
# ? L2 layer
# ===========================================================
print("Abnormal allele detection...")  # >>>

X_real = onehot_encode_seq(df_real.seq.compute())

del df_real["seq"]  # <<<

model_ = Model(model.get_layer(index=0).input, model.get_layer(index=-2).output)
# model_.summary()

train_vector = model_.predict(X_train, verbose=0, batch_size=32)
predict_vector = model_.predict(X_real, verbose=0, batch_size=32)

del X_train  # <<<

# ===========================================================
# ? LocalOutlierFactor
# ===========================================================

clf = LocalOutlierFactor(
    n_neighbors=20,
    metric="euclidean",
    contamination="auto",
    leaf_size=30,
    novelty=True,
    n_jobs=threads,
)

clf.fit(train_vector)

outliers = clf.predict(predict_vector)
outliers = np.where(outliers == 1, "normal", "abnormal")
pd.Series(outliers).value_counts()

df_real["outliers"] = outliers

df_real.groupby("barcodeID").outliers.value_counts()
# df_real
# df_real[df_real.outliers == "abnormal"]
# df_real[df_real.seqID.str.contains("^977f")]
# df_real[df_real.seqID.str.contains("^000650e8")]
################################################################################
#! Prediction
################################################################################
print("Alleye type prediction...")  # >>>

iter_ = 1000
prediction = np.zeros(X_real.shape[0], dtype="uint8")
for i in range(0, X_real.shape[0], iter_):
    predict_ = model.predict(
        X_real[i : i + iter_].astype("float16"), verbose=0, batch_size=32
    )
    prediction[i : i + iter_] = np.argmax(predict_, axis=1)

del X_real  # <<<

df_real["prediction"] = prediction
df_real["prediction"].mask(df_real["outliers"] == "abnormal", "abnormal", inplace=True)

del df_real["outliers"]  # <<<

for index, label in enumerate(labels_index):
    label = label.replace("_simulated", "")
    df_real["prediction"].mask(df_real["prediction"] == index, label, inplace=True)

# ---------------------------------------
# * In the case of a point mutation, the reads determined to be wt_ins and wt_del should be treated as "abnormal".
# ---------------------------------------
if mutation_type == "P":
    df_real["prediction"].mask(
        df_real["prediction"].str.contains("wt_"), "abnormal", inplace=True
    )

df_real.groupby("barcodeID").prediction.value_counts()

df_real.to_csv(
    ".DAJIN_temp/data/DAJIN_MIDS_prediction_result.txt",
    header=False,
    index=False,
    sep="\t",
)

