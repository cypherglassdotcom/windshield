import './main.css';
import { Main } from './Main.elm';
import registerServiceWorker from './registerServiceWorker';

const STORAGE_KEY = "CGWINDSHIELD"

const SOCKET_SERVER = window.APP_SOCKET_SERVER || process.env.ELM_APP_SOCKET_SERVER
const BACKEND_SERVER = window.APP_BACKEND_SERVER || process.env.ELM_APP_BACKEND_SERVER

const storageBody = localStorage.getItem(STORAGE_KEY)
const loadedUser = storageBody ? JSON.parse(storageBody) :
  { userName: "", token: "", expiration: 0 }

const flags = { user: loadedUser, socketServer: SOCKET_SERVER, backendServer: BACKEND_SERVER }

const app = Main.embed(document.getElementById('root'), flags)


const alarmAudio = new Audio('notification.wav');
alarmAudio.play();

app.ports.playSound.subscribe(() => {
  alarmAudio.play();
})

app.ports.signedIn.subscribe(user => {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(user))
})

app.ports.signOut.subscribe(user => {
  localStorage.removeItem(STORAGE_KEY)
})

registerServiceWorker();
