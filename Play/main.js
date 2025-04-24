// DOM 元素
const remoteVideo = document.getElementById('remote-video');
const wsAddressInput = document.getElementById('ws-address');
const connectButton = document.getElementById('connect-button');
const disconnectButton = document.getElementById('disconnect-button');
const webrtcStatusSpan = document.getElementById('webrtc-status');
const wsStatusSpan = document.getElementById('ws-status');
const noVideoMessage = document.getElementById('no-video-message');

// WebRTC 和 WebSocket 变量
let peerConnection = null;
let ws = null;

// 信令消息类型
const SignalingMessageType = {
    OFFER: 'offer',
    ANSWER: 'answer',
    CANDIDATE: 'candidate'
};

// WebSocket 函数

function connectWebSocket() {
    const wsAddress = wsAddressInput.value.trim();
    if (!wsAddress) {
        updateWsStatus('Error: Address required');
        return;
    }

    if (ws && ws.readyState === WebSocket.OPEN) {
        return;
    }

    updateWsStatus('Connecting...');
    updateVideoMessage('Connecting WebSocket...');

    ws = new WebSocket(wsAddress);

    ws.onopen = () => {
        updateWsStatus('Connected');
        connectButton.disabled = true;
        disconnectButton.disabled = false;
        wsAddressInput.disabled = true;
        updateVideoMessage('WebSocket connected. Waiting for offer...');
        initializePeerConnection();
    };

    ws.onmessage = (event) => {
        try {
            const message = JSON.parse(event.data);
            handleSignalingMessage(message);
        } catch (error) {
            console.error('Failed to parse message:', error);
        }
    };

    ws.onerror = (error) => {
        const errorMsg = error.message || 'Connection failed';
        updateWsStatus(`Error: ${errorMsg}`);
        updateVideoMessage(`WebSocket Error: ${errorMsg}`);
        disconnectWebSocket(false);
    };

    ws.onclose = (event) => {
        const reasonText = event.reason ? ` (${event.reason})` : '';
        const statusMsg = `Closed (${event.code})${reasonText}`;

        if (wsStatusSpan.textContent !== 'Disconnecting...') {
            updateWsStatus(statusMsg);
            updateVideoMessage(`WebSocket Closed (${event.code})`);
        }

        ws = null;
        connectButton.disabled = false;
        disconnectButton.disabled = true;
        wsAddressInput.disabled = false;

        if (peerConnection) {
            closePeerConnection();
        }
    };
}

function disconnectWebSocket(sendClose = true) {
    if (ws) {
        updateWsStatus('Disconnecting...');
        updateVideoMessage('Disconnecting...');
        if (sendClose && ws.readyState === WebSocket.OPEN) {
            ws.close();
        }
    }
    closePeerConnection();
}

function updateWsStatus(status) {
    wsStatusSpan.textContent = status;
}

function updateVideoMessage(message, show = true) {
    if (noVideoMessage) {
        noVideoMessage.textContent = message;
        noVideoMessage.style.display = show ? 'block' : 'none';
    }
}

function sendSignalingMessage(message) {
    if (ws && ws.readyState === WebSocket.OPEN) {
        try {
            ws.send(JSON.stringify(message));
        } catch (error) {
            console.error('Failed to send message:', error);
        }
    } else {
        updateWsStatus('Error: Not connected');
    }
}

// WebRTC 函数

function initializePeerConnection() {
    if (peerConnection) return;

    updateWebRTCStatus('Initializing...');
    const configuration = { iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] };

    try {
        peerConnection = new RTCPeerConnection(configuration);

        peerConnection.onicecandidate = event => {
            if (event.candidate) {
                const candidatePayload = {
                    sdp: event.candidate.candidate,
                    sdpMLineIndex: event.candidate.sdpMLineIndex,
                    sdpMid: event.candidate.sdpMid
                };
                sendSignalingMessage({ type: SignalingMessageType.CANDIDATE, candidate: candidatePayload });
            }
        };

        peerConnection.oniceconnectionstatechange = () => {
            const state = peerConnection.iceConnectionState;
            updateWebRTCStatus(state);

            if (['disconnected', 'failed', 'closed'].includes(state)) {
                updateVideoMessage(`WebRTC ${state}`);
                remoteVideo.srcObject = null;
            } else if (state === 'connected') {
                updateVideoMessage('', false);
            }
        };

        peerConnection.ontrack = event => {
            if (event.streams && event.streams[0]) {
                remoteVideo.srcObject = event.streams[0];
                updateVideoMessage('', false);
            } else if (!remoteVideo.srcObject && event.track) {
                let inboundStream = new MediaStream();
                inboundStream.addTrack(event.track);
                remoteVideo.srcObject = inboundStream;
                updateVideoMessage('', false);
            }
        };

        // 设置仅接收视频
        peerConnection.addTransceiver('video', { direction: 'recvonly' });

        updateWebRTCStatus('Initialized (Waiting for Offer)');
    } catch (error) {
        updateWebRTCStatus(`Error: ${error.message}`);
        updateVideoMessage(`WebRTC Init Error: ${error.message}`);
    }
}

function closePeerConnection() {
    if (peerConnection) {
        peerConnection.close();
        peerConnection = null;
        remoteVideo.srcObject = null;
        updateWebRTCStatus('Closed');
        updateVideoMessage('Connection Closed');
    }
}

async function handleOffer(offerSdp) {
    if (!peerConnection) {
        updateWebRTCStatus('Error: Not initialized');
        return;
    }

    updateWebRTCStatus('Processing Offer...');
    try {
        const offerDescription = new RTCSessionDescription({ type: 'offer', sdp: offerSdp });
        await peerConnection.setRemoteDescription(offerDescription);

        updateWebRTCStatus('Creating Answer...');
        const answerDescription = await peerConnection.createAnswer();
        await peerConnection.setLocalDescription(answerDescription);

        sendSignalingMessage({ type: SignalingMessageType.ANSWER, sessionDescription: answerDescription.sdp });
        updateWebRTCStatus('Answer Sent');
    } catch (error) {
        updateWebRTCStatus(`Error: ${error.message}`);
        updateVideoMessage(`Offer/Answer Error: ${error.message}`);
        closePeerConnection();
    }
}

async function handleCandidate(candidatePayload) {
    if (!peerConnection) return;

    try {
        const candidate = new RTCIceCandidate({
            candidate: candidatePayload.sdp,
            sdpMLineIndex: candidatePayload.sdpMLineIndex,
            sdpMid: candidatePayload.sdpMid
        });
        await peerConnection.addIceCandidate(candidate);
    } catch (error) {
        console.error('Error adding ICE candidate:', error);
    }
}

function handleSignalingMessage(message) {
    if (!message || !message.type) return;

    switch (message.type) {
        case SignalingMessageType.OFFER:
            if (message.sessionDescription) {
                handleOffer(message.sessionDescription);
            }
            break;
        case SignalingMessageType.CANDIDATE:
            if (message.candidate) {
                handleCandidate(message.candidate);
            }
            break;
        case SignalingMessageType.ANSWER:
            // 不应该收到观看者的回答
            break;
    }
}

function updateWebRTCStatus(status) {
    const displayStatus = status.charAt(0).toUpperCase() + status.slice(1);
    webrtcStatusSpan.textContent = displayStatus;
}

// 事件监听器
connectButton.addEventListener('click', connectWebSocket);
disconnectButton.addEventListener('click', () => disconnectWebSocket(true));

// 初始状态
updateWebRTCStatus('Idle');
updateWsStatus('Disconnected');
updateVideoMessage('Enter WebSocket address and connect.');
