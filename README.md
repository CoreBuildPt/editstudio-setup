# EditStudio: preparação da máquina

Script que prepara uma sessão do **Claude Code na web** para editar vídeos com o kit do EditStudio: ffmpeg 9,
Python com faster-whisper, HyperFrames com o Chrome que ele usa, bibliotecas do sistema e os modelos de transcrição.
Só usa sites da lista de rede "Trusted" do Claude Code (GitHub, PyPI, npm, Ubuntu, storage.googleapis.com).

## Usar no ambiente do Claude Code (uma vez)

Em claude.ai/code, no seletor do ambiente por baixo da caixa de mensagem: **Editar ambiente → Script de preparação**,
cola isto e grava:

```bash
#!/bin/bash
git clone -q --depth 1 https://github.com/CoreBuildPt/editstudio-setup /tmp/editstudio-setup && bash /tmp/editstudio-setup/setup.sh /tmp/editstudio-setup
```

A primeira sessão demora uns minutos a preparar; as seguintes começam logo (o Claude Code guarda a máquina pronta).
Sem este passo funciona na mesma: o kit instala tudo no arranque de cada sessão, mas demora mais.

## Modelos (release `modelos-v1`)

- `whisper-small.tar`, `whisper-medium.tar`: modelos Whisper convertidos para CTranslate2 pela Systran
  (faster-whisper), licença MIT, iguais aos do Hugging Face `Systran/faster-whisper-small` e `-medium`.
- `face_detection_yunet_2023mar.onnx`: YuNet do OpenCV Zoo, licença MIT.

O ffmpeg vem das builds do BtbN no GitHub e o modelo RVM do repositório original (PeterL1n/RobustVideoMatting).
