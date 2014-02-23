/*
   Copyright (C) 2014 Christian Dywan <christian@twotoasts.de>

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   See the file COPYING for the full license text.
*/

namespace ExternalApplications {
    static string get_commandline (AppInfo app_info) {
        return app_info.get_commandline () ?? app_info.get_executable ();
    }

    static string describe_app_info (AppInfo app_info) {
        string name = app_info.get_display_name () ?? (Path.get_basename (app_info.get_executable ()));
        string desc = app_info.get_description () ?? get_commandline (app_info);
        return Markup.printf_escaped ("<b>%s</b>\n%s", name, desc);
    }

    private class Chooser : Gtk.VBox {
        Gtk.ListStore store = new Gtk.ListStore (1, typeof (AppInfo));
        Gtk.TreeView treeview;
        List<AppInfo> available;

        public Chooser (string uri, string content_type) {
            Gtk.TreeViewColumn column;

            treeview = new Gtk.TreeView.with_model (store);
            treeview.headers_visible = false;

            store.set_sort_column_id (0, Gtk.SortType.ASCENDING);
            store.set_sort_func (0, tree_sort_func);

            column = new Gtk.TreeViewColumn ();
            Gtk.CellRendererPixbuf renderer_icon = new Gtk.CellRendererPixbuf ();
            column.pack_start (renderer_icon, false);
            column.set_cell_data_func (renderer_icon, on_render_icon);
            treeview.append_column (column);

            column = new Gtk.TreeViewColumn ();
            column.set_sizing (Gtk.TreeViewColumnSizing.AUTOSIZE);
            Gtk.CellRendererText renderer_text = new Gtk.CellRendererText ();
            column.pack_start (renderer_text, true);
            column.set_expand (true);
            column.set_cell_data_func (renderer_text, on_render_text);
            treeview.append_column (column);

            treeview.row_activated.connect (row_activated);
            treeview.show ();
            var scrolled = new Gtk.ScrolledWindow (null, null);
            scrolled.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
            scrolled.add (treeview);
            pack_start (scrolled);
            int height;
            treeview.create_pango_layout ("a\nb").get_pixel_size (null, out height);
            scrolled.set_size_request (-1, height * 5);

            available = new List<AppInfo> ();
            foreach (var app_info in AppInfo.get_all_for_type (content_type))
                launcher_added (app_info, uri);

            if (store.iter_n_children (null) < 1) {
                foreach (var app_info in AppInfo.get_all ())
                    launcher_added (app_info, uri);
            }
        }

        public List<AppInfo> get_available () {
            return available.copy ();
        }

        public AppInfo get_app_info () {
            Gtk.TreeIter iter;
            if (treeview.get_selection ().get_selected (null, out iter)) {
                AppInfo app_info;
                store.get (iter, 0, out app_info);
                return app_info;
            }
            assert_not_reached ();
        }

        void on_render_icon (Gtk.CellLayout column, Gtk.CellRenderer renderer,
            Gtk.TreeModel model, Gtk.TreeIter iter) {

            AppInfo app_info;
            model.get (iter, 0, out app_info);

            renderer.set ("gicon", app_info.get_icon (),
                          "stock-size", Gtk.IconSize.DIALOG,
                          "xpad", 4);
        }

        void on_render_text (Gtk.CellLayout column, Gtk.CellRenderer renderer,
            Gtk.TreeModel model, Gtk.TreeIter iter) {

            AppInfo app_info;
            model.get (iter, 0, out app_info);
            renderer.set ("markup", describe_app_info (app_info),
                          "ellipsize", Pango.EllipsizeMode.END);
        }

        void launcher_added (AppInfo app_info, string uri) {
#if !HAVE_WIN32
            /* On Win32 supports_uris is not implemented */
            if (!uri.has_prefix ("file://") && !app_info.supports_uris ())
                return;
#endif
            if (!app_info.should_show ())
                return;

            Gtk.TreeIter iter;
            store.append (out iter);
            store.set (iter, 0, app_info);

            available.append (app_info);
        }

        int tree_sort_func (Gtk.TreeModel model, Gtk.TreeIter a, Gtk.TreeIter b) {
            AppInfo app_info1, app_info2;
            model.get (a, 0, out app_info1);
            model.get (b, 0, out app_info2);
            return strcmp (app_info1.get_display_name (), app_info2.get_display_name ());
        }

        void row_activated (Gtk.TreePath path, Gtk.TreeViewColumn column) {
            Gtk.TreeIter iter;
            if (store.get_iter (out iter, path)) {
                AppInfo app_info;
                store.get (iter, 0, out app_info);
                selected (app_info);
            }
        }

        public signal void selected (AppInfo app_info);
    }

    class ChooserDialog : Gtk.Dialog {
        public Chooser chooser { get; private set; }

        public ChooserDialog (string uri, string content_type, Gtk.Widget widget) {
            string filename;
            if (uri.has_prefix ("file://"))
                filename = Midori.Download.get_basename_for_display (uri);
            else
                filename = uri;

            var browser = Midori.Browser.get_for_widget (widget);
            transient_for = browser;

            title = _("Choose application");
#if !HAVE_GTK3
            has_separator = false;
#endif
            destroy_with_parent = true;
            set_icon_name (Gtk.STOCK_OPEN);
            resizable = false;
            add_buttons (Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                         Gtk.STOCK_OPEN, Gtk.ResponseType.ACCEPT);

            var vbox = new Gtk.VBox (false, 8);
            vbox.border_width = 8;
            (get_content_area () as Gtk.Box).pack_start (vbox, true, true, 8);
            var label = new Gtk.Label (_("Select an application to open \"%s\"".printf (filename)));
            label.ellipsize = Pango.EllipsizeMode.MIDDLE;
            vbox.pack_start (label, false, false, 0);
            if (uri == "")
                label.no_show_all = true;
            chooser = new Chooser (uri, content_type);
            vbox.pack_start (chooser, true, true, 0);

            get_content_area ().show_all ();
            set_default_response (Gtk.ResponseType.ACCEPT);
            chooser.selected.connect ((app_info) => {
                response (Gtk.ResponseType.ACCEPT);
            });
        }

        public AppInfo? open_with () {
            show ();
            bool accept = run () == Gtk.ResponseType.ACCEPT;
            hide ();

            if (!accept)
                return null;
            return chooser.get_app_info ();
        }
    }

    class ChooserButton : Gtk.Button {
        public AppInfo? app_info { get; set; }
        public string? commandline { get; set; }
        ChooserDialog dialog;
        Gtk.Label app_name;
        Gtk.Image icon;

        public ChooserButton (string mime_type, string? commandline) {
            string content_type = ContentType.from_mime_type (mime_type);
            dialog = new ChooserDialog ("", content_type, this);
            app_info = null;
            foreach (var candidate in dialog.chooser.get_available ()) {
                if (get_commandline (candidate) == commandline)
                    app_info = candidate;
            }

            var hbox = new Gtk.HBox (false, 4);
            icon = new Gtk.Image ();
            hbox.pack_start (icon, true, true, 0);
            app_name = new Gtk.Label (null);
            app_name.use_markup = true;
            app_name.ellipsize = Pango.EllipsizeMode.END;
            hbox.pack_start (app_name, true, true, 0);
            add (hbox);
            show_all ();
            update_label ();

            clicked.connect (() => {
                app_info = dialog.open_with ();
                string new_commandline = app_info != null ? get_commandline (app_info) : null;
                commandline = new_commandline;
                selected (new_commandline);
                update_label ();
            });
        }

        void update_label () {
            app_name.label = app_info != null ? describe_app_info (app_info).replace ("\n", " ") : _("None");
            icon.set_from_gicon (app_info != null ? app_info.get_icon () : null, Gtk.IconSize.BUTTON);
        }

        public signal void selected (string? commandline);
    }

    class Types : Gtk.VBox {
        public Gtk.ListStore store = new Gtk.ListStore (2, typeof (string), typeof (AppInfo));
        Gtk.TreeView treeview;

        public Types () {
            Gtk.TreeViewColumn column;

            treeview = new Gtk.TreeView.with_model (store);
            treeview.headers_visible = false;

            store.set_sort_column_id (0, Gtk.SortType.ASCENDING);
            store.set_sort_func (0, tree_sort_func);

            column = new Gtk.TreeViewColumn ();
            column.set_sizing (Gtk.TreeViewColumnSizing.AUTOSIZE);
            Gtk.CellRendererPixbuf renderer_type_icon = new Gtk.CellRendererPixbuf ();
            column.pack_start (renderer_type_icon, false);
            column.set_cell_data_func (renderer_type_icon, on_render_type_icon);
            treeview.append_column (column);

            column = new Gtk.TreeViewColumn ();
            column.set_sizing (Gtk.TreeViewColumnSizing.AUTOSIZE);
            Gtk.CellRendererText renderer_type_text = new Gtk.CellRendererText ();
            column.pack_start (renderer_type_text, true);
            column.set_cell_data_func (renderer_type_text, on_render_type_text);
            treeview.append_column (column);

            column = new Gtk.TreeViewColumn ();
            column.set_sizing (Gtk.TreeViewColumnSizing.AUTOSIZE);
            Gtk.CellRendererPixbuf renderer_icon = new Gtk.CellRendererPixbuf ();
            column.pack_start (renderer_icon, false);
            column.set_cell_data_func (renderer_icon, on_render_icon);
            treeview.append_column (column);

            column = new Gtk.TreeViewColumn ();
            column.set_sizing (Gtk.TreeViewColumnSizing.AUTOSIZE);
            Gtk.CellRendererText renderer_text = new Gtk.CellRendererText ();
            column.pack_start (renderer_text, true);
            column.set_expand (true);
            column.set_cell_data_func (renderer_text, on_render_text);
            treeview.append_column (column);

            treeview.row_activated.connect (row_activated);
            treeview.show ();
            var scrolled = new Gtk.ScrolledWindow (null, null);
            scrolled.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
            scrolled.add (treeview);
            pack_start (scrolled);
            int height;
            treeview.create_pango_layout ("a\nb").get_pixel_size (null, out height);
            scrolled.set_size_request (-1, height * 5);

            foreach (string content_type in ContentType.list_registered ())
                launcher_added (content_type);
            foreach (string scheme in Vfs.get_default ().get_supported_uri_schemes ())
                launcher_added ("x-scheme-handler/" + scheme);

            treeview.size_allocate.connect_after ((allocation) => {
                treeview.columns_autosize ();
            });
        }

        void on_render_type_icon (Gtk.CellLayout column, Gtk.CellRenderer renderer,
            Gtk.TreeModel model, Gtk.TreeIter iter) {

            string content_type;
            store.get (iter, 0, out content_type);

            renderer.set ("gicon", ContentType.get_icon (content_type),
                          "stock-size", Gtk.IconSize.BUTTON,
                          "xpad", 4);
        }

        void on_render_type_text (Gtk.CellLayout column, Gtk.CellRenderer renderer,
            Gtk.TreeModel model, Gtk.TreeIter iter) {

            string content_type;
            AppInfo app_info;
            store.get (iter, 0, out content_type, 1, out app_info);

            string desc, mime_type;
            if (content_type.has_prefix ("x-scheme-handler/")) {
                desc = content_type.split ("/")[1] + "://";
                mime_type = "";
            } else {
                desc = ContentType.get_description (content_type);
                mime_type = ContentType.get_mime_type (content_type);
            }

            renderer.set ("markup",
                Markup.printf_escaped ("<b>%s</b>\n%s",
                    desc, mime_type),
                          "ellipsize", Pango.EllipsizeMode.END);
        }

        void on_render_icon (Gtk.CellLayout column, Gtk.CellRenderer renderer,
            Gtk.TreeModel model, Gtk.TreeIter iter) {

            AppInfo app_info;
            model.get (iter, 1, out app_info);

            renderer.set ("gicon", app_info.get_icon (),
                          "stock-size", Gtk.IconSize.MENU,
                          "xpad", 4);
        }

        void on_render_text (Gtk.CellLayout column, Gtk.CellRenderer renderer,
            Gtk.TreeModel model, Gtk.TreeIter iter) {

            AppInfo app_info;
            model.get (iter, 1, out app_info);
            renderer.set ("markup", describe_app_info (app_info),
                          "ellipsize", Pango.EllipsizeMode.END);
        }

        void launcher_added (string content_type) {
            var app_info = AppInfo.get_default_for_type (content_type, false);
            if (app_info == null)
                return;

            Gtk.TreeIter iter;
            store.append (out iter);
            store.set (iter, 0, content_type, 1, app_info);
        }

        int tree_sort_func (Gtk.TreeModel model, Gtk.TreeIter a, Gtk.TreeIter b) {
            string content_type1, content_type2;
            model.get (a, 0, out content_type1);
            model.get (b, 0, out content_type2);
            return strcmp (content_type1, content_type2);
        }

        void row_activated (Gtk.TreePath path, Gtk.TreeViewColumn column) {
            Gtk.TreeIter iter;
            if (store.get_iter (out iter, path)) {
                string content_type;
                store.get (iter, 0, out content_type);
                selected (content_type, iter);
            }
        }

        public signal void selected (string content_type, Gtk.TreeIter iter);
    }


    private class Manager : Midori.Extension {
        bool open_app_info (AppInfo app_info, string uri, string content_type) {
            Midori.URI.recursive_fork_protection (uri, true);

            try {
                var uris = new List<File> ();
                uris.append (File.new_for_uri (uri));
                app_info.launch (uris, null);
                try {
                    app_info.set_as_last_used_for_type (content_type);
                    app_info.set_as_default_for_type (content_type);
                } catch (IOError.NOT_SUPPORTED io_error) {
                    warning ("Failed to update defaults for \"%s\": %s", content_type, io_error.message);
                }
                return true;
            } catch (Error error) {
                warning ("Failed to open \"%s\": %s", uri, error.message);
                return false;
            }
        }

        bool open_uri (Midori.Tab tab, string uri) {
            return try_open (uri, get_content_type (uri, null), tab);
        }

        bool navigation_requested (WebKit.WebView web_view, WebKit.WebFrame frame, WebKit.NetworkRequest request,
            WebKit.WebNavigationAction action, WebKit.WebPolicyDecision decision) {

            string uri = request.uri;
            if (Midori.URI.is_http (uri) || Midori.URI.is_blank (uri))
                return false;

            decision.ignore ();

            string content_type = get_content_type (uri, null);
            try_open (uri, content_type, web_view);
            return true;
        }

        string get_content_type (string uri, string? mime_type) {
            if (!uri.has_prefix ("file://") && !Midori.URI.is_http (uri)) {
                string protocol = uri.split(":", 2)[0];
                return "x-scheme-handler/" + protocol;
            } else if (mime_type == null) {
                string filename;
                bool uncertain;
                try {
                    filename = Filename.from_uri (uri);
                } catch (Error error) {
                    filename = uri;
                }
                return ContentType.guess (filename, null, out uncertain);
            }
            return ContentType.from_mime_type (mime_type);
        }

        bool try_open (string uri, string content_type, Gtk.Widget widget) {
            var app_info = AppInfo.get_default_for_type (content_type, !uri.has_prefix ("file://"));
            if (app_info != null && open_app_info (app_info, uri, content_type))
                return true;
            if (open_with (uri, content_type, widget) != null)
                return true;
            return false;
        }

        AppInfo? open_with (string uri, string content_type, Gtk.Widget widget) {
            var dialog = new ChooserDialog (uri, content_type, widget);

            var app_info = dialog.open_with ();
            dialog.destroy ();

            if (uri == "")
                return app_info;

            if (app_info == null)
                return app_info;

            return open_app_info (app_info, uri, content_type) ? app_info : null;
        }

        void context_menu (Midori.Tab tab, WebKit.HitTestResult hit_test_result, Midori.ContextAction menu) {
            if ((hit_test_result.context & WebKit.HitTestResultContext.LINK) != 0)  {
                string uri = hit_test_result.link_uri;
                var action = new Gtk.Action ("OpenWith", _("Open _with…"), null, null);
                action.activate.connect ((action) => {
                    open_with (uri, get_content_type (uri, null), tab);
                });
                menu.add (action);
            }
#if !HAVE_WEBKIT2
            if ((hit_test_result.context & WebKit.HitTestResultContext.IMAGE) != 0) {
                string uri = hit_test_result.image_uri;
                var action = new Gtk.Action ("OpenImageInViewer", _("Open in Image _Viewer"), null, null);
                action.activate.connect ((action) => {
                    var download = new WebKit.Download (new WebKit.NetworkRequest (uri));
                    download.destination_uri = Midori.Download.prepare_destination_uri (download, null);
                    if (!Midori.Download.has_enough_space (download, download.destination_uri))
                        return;
                    download.notify["status"].connect ((pspec) => {
                        if (download.status == WebKit.DownloadStatus.FINISHED) {
                            try_open (download.destination_uri, get_content_type (download.destination_uri, null), tab);
                        }
                        else if (download.status == WebKit.DownloadStatus.ERROR)
                            Midori.show_message_dialog (Gtk.MessageType.ERROR,
                                _("Error downloading the image!"),
                                _("Can not download selected image."), false);
                    });
                    download.start ();
                });
                menu.add (action);
            }
#endif
        }

        void show_preferences (Katze.Preferences preferences) {
            var settings = get_app ().settings;
            var category = preferences.add_category (_("File Types"), Gtk.STOCK_FILE);
            preferences.add_group (null);
            var label = new Gtk.Label (_("Text Editor"));
            label.set_alignment (0.0f, 0.5f);
            preferences.add_widget (label, "indented");
            var entry = new ChooserButton ("text/plain", settings.text_editor);
            entry.selected.connect ((commandline) => {
                settings.text_editor = commandline;
            });
            preferences.add_widget (entry, "spanned");

            label = new Gtk.Label (_("News Aggregator"));
            label.set_alignment (0.0f, 0.5f);
            preferences.add_widget (label, "indented");
            entry = new ChooserButton ("application/rss+xml", settings.news_aggregator);
            entry.selected.connect ((commandline) => {
                settings.news_aggregator = commandline;
            });
            preferences.add_widget (entry, "spanned");

            var types = new Types ();
            types.selected.connect ((content_type, iter) => {
                var app_info = open_with ("", content_type, preferences);
                if (app_info == null)
                    return;
                try {
                    app_info.set_as_default_for_type (content_type);
                    types.store.set (iter, 1, app_info);
                } catch (Error error) {
                    warning ("Failed to select default for \"%s\": %s", content_type, error.message);
                }
            });
            category.pack_start (types, true, true, 0);
            types.show_all ();
        }

        public void tab_added (Midori.Browser browser, Midori.View view) {
            view.web_view.navigation_policy_decision_requested.connect (navigation_requested);
            view.open_uri.connect (open_uri);
            view.context_menu.connect (context_menu);
        }

        public void tab_removed (Midori.Browser browser, Midori.View view) {
            view.web_view.navigation_policy_decision_requested.disconnect (navigation_requested);
            view.open_uri.disconnect (open_uri);
            view.context_menu.disconnect (context_menu);
        }

        void browser_added (Midori.Browser browser) {
            foreach (var tab in browser.get_tabs ())
                tab_added (browser, tab);
            browser.add_tab.connect (tab_added);
            browser.remove_tab.connect (tab_removed);
            browser.show_preferences.connect (show_preferences);
        }

        void activated (Midori.App app) {
            foreach (var browser in app.get_browsers ())
                browser_added (browser);
            app.add_browser.connect (browser_added);
        }

        void browser_removed (Midori.Browser browser) {
            foreach (var tab in browser.get_tabs ())
                tab_removed (browser, tab);
            browser.add_tab.disconnect (tab_added);
            browser.remove_tab.disconnect (tab_removed);
            browser.show_preferences.disconnect (show_preferences);
        }

        void deactivated () {
            var app = get_app ();
            foreach (var browser in app.get_browsers ())
                browser_removed (browser);
            app.add_browser.disconnect (browser_added);

        }

        internal Manager () {
            GLib.Object (name: "External Applications",
                         description: "Choose what to open unknown file types with",
                         version: "0.1" + Midori.VERSION_SUFFIX,
                         authors: "Christian Dywan <christian@twotoasts.de>");

            this.activate.connect (activated);
            this.deactivate.connect (deactivated);
        }
    }
}

public Midori.Extension extension_init () {
    return new ExternalApplications.Manager ();
}

