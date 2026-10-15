package nl.softphone.app

import android.app.Activity
import android.app.Application
import android.os.Bundle

class App : Application() {

    override fun onCreate() {
        super.onCreate()
        Notifs.createChannels(this)
        Sip.init(this)
        PhoneService.start(this)

        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityStarted(activity: Activity) { startedActivities++ }
            override fun onActivityStopped(activity: Activity) { startedActivities-- }
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
    }

    companion object {
        private var startedActivities = 0
        val inForeground: Boolean get() = startedActivities > 0
    }
}
